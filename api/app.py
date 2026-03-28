from __future__ import annotations

import sys
import os
import json
from datetime import date
from typing import Generator

import logging

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from langchain_openai import ChatOpenAI
from dotenv import load_dotenv
from datetime import datetime, timedelta
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_HERE     = os.path.dirname(os.path.abspath(__file__))
_SRC_CORE = os.path.abspath(os.path.join(_HERE, "../src/core"))

# Load .env from project root
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../.env"))


for _p in (_HERE, _SRC_CORE):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from src.core.main_graph import main_graph
from schemas import GenerateRequest, GenerateResponse, HealthResponse

app = FastAPI(
    title="Blog Generation Agent API",
    description="LangGraph-powered technical blog generator",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("outputs/images", exist_ok=True)
app.mount("/outputs", StaticFiles(directory="outputs"), name="outputs")

# Node display names for the frontend progress stream
NODE_LABELS = {
    "router":                    "Analysing topic & deciding research mode",
    "research":                  "Searching the web for evidence",
    "orchestrator":              "Planning blog structure",
    "worker":                    "Writing sections",
    "reducer":                   "Merging & finalising content",
    "merge_content":             "Assembling sections",
    "decide_images":             "Deciding image placements",
    "generate_and_place_images": "Generating images",
}


def _build_initial_state(topic: str, output_dir: str) -> dict:
    return {
        "topic": topic,
        "as_of": date.today().isoformat(),
        "recency_days": 0,
        "mode": "closed_book",
        "needs_research": False,
        "queries": [],
        "evidence": [],
        "plan": None,
        "sections": [],
        "merged_md": "",
        "md_with_placeholders": "",
        "image_specs": [],
        "final": "",
    }


def _stream_generation(topic: str, model: str, output_dir: str) -> Generator[str, None, None]:
    """
    Runs graph.stream() and yields SSE-formatted events.
    Event types:
      - node_done : a pipeline node completed
      - result    : final markdown content
      - error     : something went wrong
    """
    from pathlib import Path
    from src.core.utils import _safe_slug

    def sse(event: str, data: dict) -> str:
        return f"event: {event}\ndata: {json.dumps(data)}\n\n"

    try:
        graph = main_graph()
        llm = ChatOpenAI(model=model, temperature=0.3)
        config = {"configurable": {"llm": llm, "output_dir": output_dir}}
        initial_state = _build_initial_state(topic, output_dir)

        seen_nodes: set[str] = set()
        final_state: dict = {}

        # stream_mode="updates" gives us {node_name: node_output} per step
        for chunk in graph.stream(initial_state, config=config, stream_mode="updates"):
            for node_name, node_output in chunk.items():
                # Collapse all parallel worker events into one progress tick
                if node_name == "worker" and "worker" in seen_nodes:
                    continue
                seen_nodes.add(node_name)

                label = NODE_LABELS.get(node_name, node_name.replace("_", " ").title())
                yield sse("node_done", {"node": node_name, "label": label})

                # Capture state as it accumulates
                if isinstance(node_output, dict):
                    final_state.update(node_output)

        # Pull markdown from accumulated state; fall back to reading the saved file
        md_content = final_state.get("final", "")
        filename = "blog.md"

        if not md_content:
            out_path = Path(output_dir)
            for f in sorted(out_path.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True):
                filename = f.name
                md_content = f.read_text(encoding="utf-8")
                break
        else:
            plan_data = final_state.get("plan")
            if plan_data:
                title = getattr(plan_data, "blog_title", None) or plan_data.get("blog_title", "blog")
                filename = f"{_safe_slug(title)}.md"

        yield sse("result", {"filename": filename, "markdown": md_content})

    except Exception as exc:
        logger.exception("Generation pipeline failed")
        yield sse("error", {"message": str(exc)})


@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(status="ok")


@app.post("/generate/stream")
def generate_stream(req: GenerateRequest):
    """
    SSE endpoint. Client connects and receives a stream of events:
      event: node_done  — a pipeline node completed
      event: result     — full markdown ready
      event: error      — something went wrong
    """
    os.makedirs(req.output_dir, exist_ok=True)

    return StreamingResponse(
        _stream_generation(req.topic, req.model, req.output_dir),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/generate", response_model=GenerateResponse)
def generate_sync(req: GenerateRequest):
    """
    Non-streaming endpoint. Waits for full completion and returns result.
    Useful for testing or non-SSE clients.
    """
    os.makedirs(req.output_dir, exist_ok=True)

    try:
        graph = main_graph()
        llm = ChatOpenAI(model=req.model, temperature=0.3)
        config = {"configurable": {"llm": llm, "output_dir": req.output_dir}}
        initial_state = _build_initial_state(req.topic, req.output_dir)
        final_state = graph.invoke(initial_state, config=config)
        final_md = final_state.get("final", "")

        from src.core.utils import _safe_slug
        filename = f"{_safe_slug(final_state.get('plan', {}).blog_title if final_state.get('plan') else 'blog')}.md"

        return GenerateResponse(status="ok", filename=filename, final_md=final_md)

    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    


@app.get("/blogs")
def list_blogs(output_dir: str = "outputs"):
    """Returns metadata for .md files created in the last 7 days."""
    out_path = Path(output_dir)
    if not out_path.exists():
        return {"blogs": []}

    cutoff = datetime.now() - timedelta(days=7)
    blogs = []

    for f in sorted(out_path.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True):
        mtime = datetime.fromtimestamp(f.stat().st_mtime)
        if mtime < cutoff:
            continue
        blogs.append({
            "filename": f.name,
            "created_at": mtime.isoformat(),
            "size_kb": round(f.stat().st_size / 1024, 1),
        })

    return {"blogs": blogs}


@app.get("/blogs/{filename}")
def get_blog(filename: str, output_dir: str = "outputs"):
    """Returns the markdown content of a specific blog."""
    safe_name = Path(filename).name
    file_path = Path(output_dir) / safe_name

    if not file_path.exists() or file_path.suffix != ".md":
        raise HTTPException(status_code=404, detail="Blog not found")

    return {
        "filename": safe_name,
        "markdown": file_path.read_text(encoding="utf-8"),
    }


@app.delete("/blogs/{filename}")
def delete_blog(filename: str, output_dir: str = "outputs"):
    """Deletes a blog .md file from disk."""
    safe_name = Path(filename).name
    file_path = Path(output_dir) / safe_name

    if not file_path.exists() or file_path.suffix != ".md":
        raise HTTPException(status_code=404, detail="Blog not found")

    file_path.unlink()
    return {"status": "deleted", "filename": safe_name}


_FRONTEND_DIST = Path(__file__).parent.parent / "frontend" / "dist"


@app.get("/{full_path:path}", include_in_schema=False)
def serve_frontend(full_path: str):
    """Serve the Vite SPA — return the requested file or fall back to index.html."""
    file_path = _FRONTEND_DIST / full_path
    if file_path.exists() and file_path.is_file():
        return FileResponse(file_path)
    return FileResponse(_FRONTEND_DIST / "index.html")


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("api.app:app", host="0.0.0.0", port=port, reload=False)