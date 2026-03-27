# ✦ BlogForge — AI Blog Generation Agent

A full-stack AI agent that turns any technical topic into a publication-ready blog post. Built with LangGraph for the agentic pipeline, FastAPI for the backend, and a TypeScript/Vite frontend with live streaming progress.

---

## How it works

```
Topic Input
    └─▶ Router         — decides if web research is needed (closed_book / hybrid / open_book)
    └─▶ Research       — searches the web via Tavily and synthesises evidence
    └─▶ Orchestrator   — plans the blog structure (5–9 sections)
    └─▶ Workers (×N)   — writes each section in parallel
    └─▶ Merge          — assembles sections in order
    └─▶ Image Planner  — decides where diagrams would help
    └─▶ Image Gen      — generates images via Gemini and embeds them
    └─▶ Output         — saves final .md file to disk
```

Progress streams live to the UI via Server-Sent Events (SSE) so you can watch each node complete in real time.

---

## Project structure

```
.
├── src/
│   └── core/                   # LangGraph agent
│       ├── main_graph.py       # graph topology
│       ├── nodes.py            # all node functions
│       ├── state.py            # LangGraph state schema
│       ├── conditionals.py     # routing + fanout logic
│       ├── reducer_subgraph.py # merge/image subgraph
│       ├── pydantic_models.py  # all Pydantic schemas
│       └── utils.py            # Tavily search, image gen, helpers
│
├── api/
│   ├── app.py                  # FastAPI app + SSE + sync endpoints
│   └── schemas.py              # request/response models
│
├── frontend/
│   ├── index.html
│   ├── vite.config.ts
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── main.ts             # app entry point
│       ├── api.ts              # SSE + fetch wrappers
│       ├── types.ts            # TypeScript interfaces
│       ├── components/
│       │   ├── InputPanel.ts   # topic input form
│       │   ├── ProgressStream.ts # live node progress feed
│       │   ├── ResultPanel.ts  # markdown preview + editor + download
│       │   └── Toast.ts        # notifications
│       └── styles/
│           └── main.css
│
├── outputs/                    # generated .md files saved here
├── .env.example
├── requirements.txt
└── README.md
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Python | 3.11+ | |
| Node.js | 18+ LTS | https://nodejs.org |
| npm | 9+ | bundled with Node |
| OpenAI API key | — | for LLM calls |
| Tavily API key | — | for web search (free tier available at https://tavily.com) |
| Google API key | — | for Gemini image generation (optional — app works without it) |

---

## Local setup

### 1. Clone the repo

```bash
git clone <your-repo-url>
cd Blog_Generation_Agent
```

### 2. Set up environment variables

Create a `.env` file in the project root with the following keys:
```env
OPENAI_API_KEY=sk-...
TAVILY_API_KEY=tvly-...
GOOGLE_API_KEY=...        # optional — only needed for image generation
```

### 3. Install Python dependencies

```bash
pip install -r requirements.txt
```

> **Windows tip:** if you hit a `uv trampoline` error, use `python -m pip install -r requirements.txt` instead.

### 4. Install frontend dependencies

```bash
cd frontend
npm install
cd ..
```

---

## Running locally

You need **two terminals** running simultaneously.

### Terminal 1 — Backend (FastAPI)

```bash
# From the project root
python -m uvicorn api.app:app --reload --port 8000
```

The API will be available at:
- `http://localhost:8000` — API root
- `http://localhost:8000/health` — health check
- `http://localhost:8000/docs` — auto-generated Swagger UI

### Terminal 2 — Frontend (Vite dev server)

```bash
cd frontend
npm run dev
```

The UI will be available at `http://localhost:5173`.

---

## Using the app

1. Open `http://localhost:5173` in your browser
2. Type a technical topic in the input box (e.g. *"How KV cache works in LLM inference"*)
3. Select a model (GPT-4o recommended)
4. Click **Generate Blog** or press `Cmd/Ctrl + Enter`
5. Watch the pipeline progress live in the terminal feed on the right
6. When complete:
   - **Preview** tab renders the final markdown
   - **Edit** tab lets you make changes before downloading
   - **Download** saves the `.md` file locally
   - **Copy** copies raw markdown to clipboard
7. The `.md` file is also saved automatically to the `outputs/` folder on the server

---

## API endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Health check |
| `POST` | `/generate/stream` | SSE streaming generation |
| `POST` | `/generate` | Synchronous generation (no streaming) |

### POST `/generate/stream` — request body

```json
{
  "topic": "How attention mechanisms work in transformers",
  "model": "gpt-4o",
  "output_dir": "outputs"
}
```

### SSE event types

| Event | Payload | Description |
|---|---|---|
| `node_done` | `{ "node": "router", "label": "Analysing topic" }` | A pipeline node completed |
| `result` | `{ "filename": "blog.md", "markdown": "..." }` | Final blog ready |
| `error` | `{ "message": "..." }` | Something went wrong |

---

## Configuration

### Switching models

Pass any OpenAI model name in the request body or select from the UI dropdown:

```json
{ "model": "gpt-4o-mini" }   // cheaper + faster
{ "model": "gpt-4o" }        // recommended
{ "model": "gpt-4-turbo" }   // alternative
```

### Disabling image generation

Image generation via Gemini is optional. If `GOOGLE_API_KEY` is not set, the agent will gracefully skip image generation and output a clean markdown file with placeholder blocks instead of images.

### Output directory

Generated files are saved to `outputs/` by default. You can change this per-request:

```json
{ "output_dir": "my_custom_folder" }
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `npm: not recognized` | Install Node.js from https://nodejs.org then restart your terminal |
| `npm error ENOENT package.json` | Run `npm install` from inside the `frontend/` folder, not the project root |
| `Failed to resolve import "./styles/main.css"` | Create `frontend/src/styles/` folder and ensure `main.css` is inside it |
| `uv trampoline failed` | Use `python -m uvicorn ...` and `python -m pip install ...` instead of bare commands |
| `Cannot reach the API` toast on load | Make sure the FastAPI server is running on port 8000 |
| `from schemas import ...` error | Launch uvicorn from the project root: `python -m uvicorn api.app:app ...` |

---

## Roadmap

- [x] LangGraph agentic pipeline (router → research → orchestrator → workers → reducer)
- [x] Live SSE streaming progress
- [x] Markdown preview + editor + download
- [x] FastAPI backend
- [x] TypeScript/Vite frontend
- [x] Docker setup
- [x] Fly.io deployment
- [ ] Authentication
- [ ] Blog history / saved generations
- [ ] Support for Anthropic Claude and Gemini as LLM backends

---

## Deployment

### Fly.io

The app is fully Dockerised with a multi-stage build (Node builds the frontend, Python runs the backend). Generated blogs are stored on a persistent Fly volume so they survive restarts.

#### 1. Install flyctl

```bash
curl -L https://fly.io/install.sh | sh
fly auth login
```

#### 2. Launch the app (first time only)

```bash
fly launch
```

When prompted, accept the detected `fly.toml` config. Choose a region close to you (default: `iad` — US East).

#### 3. Create the persistent volume

```bash
fly volumes create blog_outputs --size 1 --region iad
```

> The volume is mounted at `/app/outputs` inside the container, matching the path the app writes generated blogs to.

#### 4. Set your API keys as secrets

```bash
fly secrets set \
  OPENAI_API_KEY=sk-... \
  TAVILY_API_KEY=tvly-... \
  GOOGLE_API_KEY=...
```

`GOOGLE_API_KEY` is optional — skip it if you don't need image generation.

#### 5. Deploy

```bash
fly deploy
```

The build runs the multi-stage Dockerfile: installs Node deps, builds the Vite frontend, installs Python deps, then starts the FastAPI server. Your app will be live at `https://<app-name>.fly.dev`.

#### Subsequent deploys

```bash
fly deploy
```

#### Useful commands

```bash
fly logs          # stream live logs
fly status        # machine status
fly ssh console   # shell into the running container
fly volumes list  # check your persistent volume
```

---

## Tech stack

| Layer | Technology |
|---|---|
| Agent framework | LangGraph |
| LLM | OpenAI GPT-4o (via LangChain) |
| Web search | Tavily |
| Image generation | Google Gemini |
| Backend | FastAPI + Uvicorn |
| Frontend | TypeScript + Vite (no framework) |
| Streaming | Server-Sent Events (SSE) |
| Markdown rendering | marked.js |



