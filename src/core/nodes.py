from __future__ import annotations

__all__ = ["router", "research", "orchestrator", "worker", "merge_content", "decide_images"]

from langchain_core.prompts import ChatPromptTemplate
from datetime import timedelta, date
from typing import List
from langchain_core.runnables import RunnableConfig
from pathlib import Path

from state import State
from pydantic_models import RouterDecision, EvidenceItem, EvidencePack, Plan, Task, GlobalImagePlan
from utils import _tavily_search, _iso_to_date, _safe_slug, _gemini_generate_image_bytes, _save_image



def router(state: State, config: RunnableConfig) -> dict:

    llm = config["configurable"]["llm"]

    ROUTER_SYSTEM = """
    You are a routing module for a technical blog planner.

    Decide whether web research is needed BEFORE planning.

    Modes:
    - closed_book (needs_research=false):
    Evergreen topics where correctness does not depend on recent facts (concepts, fundamentals).

    - hybrid (needs_research=true):
    Mostly evergreen but needs up-to-date examples/tools/models to be useful.

    - open_book (needs_research=true):
    Mostly volatile: weekly roundups, "this week", "latest", rankings, pricing, policy/regulation.

    If needs_research=true:
    - Output 3-10 high-signal queries.
    - Queries should be scoped and specific (avoid generic queries like just "AI" or "LLM").
    - For open_book weekly roundup, include queries that reflect the last 7 days constraint.
    """
    decider = llm.with_structured_output(RouterDecision)

    router_prompt = ChatPromptTemplate.from_messages(
        [
            ("system", ROUTER_SYSTEM),
            ("human", "Topic: {topic}\nAs-of date: {as_of_date}")
        ]
    )

    router_chain = router_prompt|decider

    decision = router_chain.invoke({"topic": state['topic'], "as_of_date": state["as_of"]})

    # Set default recency window based on mode
    if decision.mode =='open_book':
        recency_days = 7
    elif decision.mode == 'hybrid':
        recency_days = 45
    else:
        recency_days = 3650

    return {
        "needs_research": decision.needs_research,
        "mode": decision.mode,
        "queries": decision.queries,
        "recency_days": recency_days,
    }


def research(state:State, config: RunnableConfig) -> dict:

    llm = config["configurable"]["llm"]

    RESEARCH_SYSTEM = """
    You are a research synthesizer for technical writing.

    Given raw web search results, produce a deduplicated list of EvidenceItem objects.

    Rules:
    - Only include items with a non-empty url.
    
    - Prefer relevant + authoritative sources (company blogs, docs, reputable outlets).
    
    - Extract/normalize published_at as ISO (YYYY-MM-DD) if you can infer it from title/snippet.
      If you can't infer a date reliably, set published_at=null (do NOT guess).

    - Keep snippets short.
    
    - Deduplicate by URL.
    """

    queries = (state.get("queries", []) or [])[:10]
    max_results = 6
    raw_results:List[dict] = []

    for q in queries:
        raw_results.extend(_tavily_search(q, max_results=max_results))

    if not raw_results:
        return {"evidence": []}
    
    extractor = llm.with_structured_output(EvidencePack)

    research_prompt = ChatPromptTemplate.from_messages(
        [
            ("system", RESEARCH_SYSTEM),
            ("human", "As-of date: {as_of_date}\nRecency Days: {recency_days}\nRaw Results: \n{raw_results}")
        ]
    )

    research_chain = research_prompt|extractor

    pack = research_chain.invoke(
        {
            "as_of_date": state['as_of'], 
            "recency_days":state['recency_days'],
            "raw_results": raw_results
        }
    )

    # Deduplicate by URL
    dedup = {}
    for e in pack.evidence:
        if e.url:
            dedup[e.url] = e

    evidence = list(dedup.values())

    # HARD RECENCY FILTER for open_book weekly roundup:
    # keep only items with a parseable ISO date and within the window.

    mode = state.get("mode", "closed_book")
    
    if mode == "open_book":
        as_of = date.fromisoformat(state["as_of"])
        cutoff = as_of - timedelta(days=int(state["recency_days"]))
        fresh: List[EvidenceItem] = []
        
        for e in evidence:
            d = _iso_to_date(e.published_at)
            if d and d >= cutoff:
                fresh.append(e)
        evidence = fresh

    return {"evidence": evidence}



def orchestrator(state: State, config: RunnableConfig) -> dict:

    llm = config["configurable"]["llm"]
    planner = llm.with_structured_output(Plan)

    topic =  state['topic']
    mode = state.get("mode", "closed_book")
    evidence = state.get("evidence", [])
    evidence_gathered = [e.model_dump() for e in evidence] if evidence else []
    
    ORCH_SYSTEM = """
    You are a senior technical writer and developer advocate.
    Your job is to produce a highly actionable outline for a technical blog post.

    Hard requirements:
    - Create 5-9 sections (tasks) suitable for the topic and audience.
    - Each task must include:
    1) goal (1 sentence)
    2) 3-5 bullets that are concrete, specific, and non-overlapping
    3) target word count (120-550)

    Flexibility:
    - Do NOT use a fixed taxonomy unless it naturally fits.
    - You may tag tasks (tags field), but tags are flexible.

    Quality bar:
    - Assume the reader is a developer; use correct terminology.
    - Bullets must be actionable: build/compare/measure/verify/debug.
    - Ensure the overall plan includes at least 2 of these somewhere:
        * minimal code sketch / MWE (set requires_code=True for that section)
        * edge cases / failure modes
        * performance/cost considerations
        * security/privacy considerations (if relevant)
        * debugging/observability tips

    Grounding rules:
    - Mode closed_book: 
        * keep it evergreen; do not depend on evidence.
    - Mode hybrid: 
        * Use evidence for up-to-date examples (models/tools/releases) in bullets.
        * Mark sections using fresh info as requires_research=True and requires_citations=True.
    - Mode open_book (weekly news roundup):
        * Set blog_kind = "news_roundup".
        * Every section is about summarizing events + implications.
        * DO NOT include tutorial/how-to sections (no scraping/RSS/how to fetch news) unless user explicitly asked for that.
        * If evidence is empty or insufficient, create a plan that transparently says "insufficient fresh sources"
          and includes only what can be supported.

    Output must strictly match the Plan schema.
    """

    human_message = """
    Topic: {topic}
    Mode: {mode}
    As-of: {as_of} (recency_days = {recency_days})

    Evidence:
    {evidence_gathered}

    """
    prompt =  ChatPromptTemplate.from_messages(
        [
            ("system", ORCH_SYSTEM),
            ("user", human_message)
        ]
    )

    chain = prompt | planner
    plan = chain.invoke(
        {
            "topic": topic,
            "mode": mode,
            "as_of": state['as_of'],
            "recency_days": state["recency_days"],
            "evidence_gathered": evidence_gathered
        }
    )

    return {"plan": plan}


def worker(payload:dict, config: RunnableConfig) -> dict:

    llm = config["configurable"]["llm"]

    # payload contains what we send
    task = Task(**payload['task'])
    topic = payload['topic']
    plan = Plan(**payload['plan'])
    evidence = [EvidenceItem(**e) for e in payload.get("evidence", [])]
    mode = payload.get("mode", "")

    bullets_text = "\n- " + "\n- ".join(task.bullets)
    evidence_text = "\n".join(
        f"- {e.title} | {e.url} | {e.published_at or 'date:unknown'}"
        for e in evidence[:20]
    )

    system_message = """
    You are a senior technical writer and developer advocate. Write ONE section of a technical blog post in Markdown.
    
    Hard constraints:
        - Follow the provided Goal and cover ALL Bullets in order (do not skip or merge bullets).
        - Stay close to the Target words (±15%).
        - Output ONLY the section content in Markdown (no blog title H1, no extra commentary).

    Technical quality bar:
        - Be precise and implementation-oriented (developers should be able to apply it).
        - Prefer concrete details over abstractions: APIs, data structures, protocols, and exact terms.
        - When relevant, include at least one of:
            * a small code snippet (minimal, correct, and idiomatic)
            * a tiny example input/output
            * a checklist of steps
            * a diagram described in text (e.g., 'Flow: A -> B -> C')
        - Explain trade-offs briefly (performance, cost, complexity, reliability).
        - Call out edge cases / failure modes and what to do about them.
        - If you mention a best practice, add the 'why' in one sentence.
        - If blog_kind=="news_roundup", do NOT drift into tutorials (scraping/RSS/how to fetch).
          Focus on events + implications.
        - If mode=="open_book": do not introduce any specific event/company/model/funding/policy claim unless 
          supported by provided Evidence URLs. For each supported claim, attach a Markdown link ([Source](URL)).
          If unsupported, write "Not found in provided sources."
        - If requires_citations==true (hybrid tasks): cite Evidence URLs for external claims.

    Code:
        - If requires_code==true, include at least one minimal snippet.
    
    Markdown style:
        - Start with a '## <Section Title>' heading.
        - Use short paragraphs, bullet lists where helpful, and code fences for code.
        - Avoid fluff. Avoid marketing language.
        - If you include code, keep it focused on the bullet being addressed.

    """

    user_mseeage = """
    Blog: {blog_title}

    Audience: {audience}

    Tone: {tone}

    Blog kind: {blog_kind}

    Constraints: {constraints}

    Topic: {topic}

    Mode: {mode}

    As-of: {as_of} (recency_days = {recency_days})

    Section title: {title}

    Section type: {section_type}

    Goal: {goal}

    Target words: {target_words}

    Tags: {tags}

    requires_research: {requires_research}

    requires_citations: {requires_citations}

    requires_code: {requires_code}

    Bullets: {bullets}

    Evidence (Only site these URLs): {evidence_text}

    Return Only the Section content in markdown.
    """

    markdown_prompt = ChatPromptTemplate.from_messages(
        [
            ("system", system_message),
            ("user", user_mseeage)
        ]
    )

    chain = markdown_prompt|llm

    result = chain.invoke(
        {
            "blog_title": plan.blog_title,
            "audience": plan.audience,
            "tone":  plan.tone,
            "blog_kind": plan.blog_kind,
            "constraints": plan.constraints,
            "topic": topic,
            "mode": mode,
            "as_of": payload.get("as_of"),
            "recency_days": payload.get("recency_days"),
            "title": task.title,
            "section_type": task.section_type,
            "goal": task.goal,
            "target_words": task.target_words,
            "tags": task.tags,
            "requires_research": task.requires_research,
            "requires_citations": task.requires_citations,
            "requires_code": task.requires_code,
            "bullets": bullets_text,
            "evidence_text":evidence_text
        }
    )

    section_md = result.content if isinstance(result.content, str) else str(result.content)
    section_md = section_md.strip()

    return {"sections": [(task.id, section_md)]}


# Reducer sub graph
# merge_content -> decide_images -> generate_and_place_images

def merge_content(state: State) -> dict:
    plan = state["plan"]
    if plan is None:
        raise ValueError("merge_content called without plan.")
    ordered_sections = [md for _, md in sorted(state["sections"], key=lambda x: x[0])]
    body = "\n\n".join(ordered_sections).strip()
    merged_md = f"# {plan.blog_title}\n\n{body}\n"
    return {"merged_md": merged_md}


def decide_images(state: State, config: RunnableConfig) -> dict:

    llm = config["configurable"]["llm"]
    DECIDE_IMAGES_SYSTEM = """
    You are an expert technical editor.
    Decide if images/diagrams are needed for THIS blog.

    Rules:
        - Max 3 images total.
        - Each image must materially improve understanding (diagram/flow/table-like visual).
        - Insert placeholders exactly: [[IMAGE_1]], [[IMAGE_2]], [[IMAGE_3]].
        - If no images needed: md_with_placeholders must equal input and images=[].
        - Avoid decorative images; prefer technical diagrams with short labels.
    
    Return strictly GlobalImagePlan.
    """

    human_message = """
    Blog kind: {blog_kind}

    Topic: {topic}

    Insert placeholders + propose image prompts

    {merged_md}
    """

    planner = llm.with_structured_output(GlobalImagePlan)
    merged_md = state["merged_md"]
    plan = state["plan"]
    assert plan is not None

    prompt = ChatPromptTemplate.from_messages(
        [
            ("system", DECIDE_IMAGES_SYSTEM),
            ("human", human_message)
        ]
    )

    chain = prompt | planner

    image_plan = chain.invoke(
        {
            "blog_kind": plan.blog_kind,
            "topic": state['topic'],
            "merged_md": merged_md
        }
    )

    return {
        "md_with_placeholders": image_plan.md_with_placeholders,
        "image_specs": [img.model_dump() for img in image_plan.images],
    }


def generate_and_place_images(state: State, config: RunnableConfig) -> dict:
    plan = state["plan"]
    assert plan is not None

    md = state.get("md_with_placeholders") or state["merged_md"]
    image_specs = state.get("image_specs", []) or []

    # resolve output directory from config, default to cwd
    output_dir = Path(config.get("configurable", {}).get("output_dir", "."))
    output_dir.mkdir(parents=True, exist_ok=True)
    images_dir = output_dir / "images"          # ← was hardcoded Path("images")
    images_dir.mkdir(exist_ok=True)

    # If no images requested, just write merged markdown
    if not image_specs:
        out_path = output_dir / f"{_safe_slug(plan.blog_title)}.md"  # ← was Path(filename)
        out_path.write_text(md, encoding="utf-8")
        return {"final": md}

    for spec in image_specs:
        placeholder = spec["placeholder"]
        img_filename = spec["filename"]
        out_path = images_dir / img_filename     # ← renamed filename → img_filename to avoid shadowing

        # generate only if needed (out_path never exists on GCS, so always uploads there)
        if not out_path.exists():
            try:
                img_bytes = _gemini_generate_image_bytes(spec["prompt"])
                img_url = _save_image(img_bytes, images_dir, img_filename)
            except Exception as e:
                # graceful fallback: keep doc usable
                prompt_block = (
                    f"> **[IMAGE GENERATION FAILED]** {spec.get('caption','')}\n>\n"
                    f"> **Alt:** {spec.get('alt','')}\n>\n"
                    f"> **Prompt:** {spec.get('prompt','')}\n>\n"
                    f"> **Error:** {e}\n"
                )
                md = md.replace(placeholder, prompt_block)
                continue
        else:
            img_url = f"images/{img_filename}"

        img_md = f"![{spec['alt']}]({img_url})\n*{spec['caption']}*"
        md = md.replace(placeholder, img_md)

    md_path = output_dir / f"{_safe_slug(plan.blog_title)}.md"  # ← was Path(filename)
    md_path.write_text(md, encoding="utf-8")
    return {"final": md}
