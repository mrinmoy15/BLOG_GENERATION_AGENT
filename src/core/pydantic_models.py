from __future__ import annotations

# __all__= []

from pydantic import BaseModel, Field
from typing import List, Literal

## All Pydantic Models

class Task(BaseModel):
    id: int
    title: str
    goal: str = Field(
        ..., 
        description = "One sentence describing what the reader should be able to do/understand after this section."
    )
    bullets: List[str] = Field(
        ..., 
        min_length=3,
        max_length=5,
        description="3-5 concrete, non-overlapping subpoints to cover in this section."
    )

    target_words: int = Field(
        ...,
        description="Target word count for this section (120-450)."
    )
    tags: List[str] = Field(
        default_factory=list,
        description="tags associated."
    )

    section_type: Literal["intro", "core", "examples", "checklist", "common_mistakes", "conclusion"] = Field(
        ..., description="Use 'common_mistakes' exactly once in the plan."
    )
    requires_research: bool = Field(
        default=False, 
        description="whether research on internet is needed or not"
    )
    requires_citations: bool = Field(
        default=False, 
        description="whether citation needs to be provided or not"
    )
    requires_code: bool = Field(
        default=False, 
        description="whether any relevant code snippet needed or not"
    )


class Plan(BaseModel):
    blog_title: str = Field(..., description="Title of the blog")
    audience: str = Field(..., description="Who is the blog targeted for?")
    tone: str = Field(..., description="Writing tone, e.g. practical, crisp")
    blog_kind: Literal["explainer", "tutorial", "news_roundup", "comparison", "system_design"] = Field(
        default = "explainer",
        description = "Tells workers what genre this is (prevents drift)"
    )
    constraints: List[str] = Field(default_factory=list, description="List of constraints to be considered.")
    tasks : List[Task] = Field(..., min_length=1, description="List of tasks formulated for the Plan.")


class EvidenceItem(BaseModel):
    title: str
    url: str
    published_at: str | None = Field(
        default = None,
        description="When is it published in the format 'YYYY-MM-DD' if available",
        examples = ["2026-01-01"]
    )
    snippet: str | None = Field(
        default = None,
        description = "Text content of the internet research if asked by the user"
    )
    source: str | None = Field(
        default=None,
        description = "Publication if available",
        examples = ["NYT", "WAPO"]
    )


class RouterDecision(BaseModel):
    needs_research: bool = Field(
        ..., 
        description="binary variable determines whether research is needed on the internet or not."
    )
    mode: Literal["closed_book", "hybrid", "open_book"] = Field(
        ...,
        description = """
        Mode of answering,
            closed_book if the answer is totally contained in the llm's knowledge
            open_book if the answer is totally based on internet search
            hybrid when the answer contain both contents from llm's knowledge as well as internet search
        """
    )
    reason: str = Field(
        description = "Reason to choose a particular mode"
    )
    queries: List[str] = Field(
        default_factory=list,
        description="The list of queries generated based on the user's input topic."
    )


class EvidencePack(BaseModel):
    evidence: List[EvidenceItem] = Field(default_factory=list)


# ---- Image planning schema (ported from your image flow) ----

class ImageSpec(BaseModel):
    placeholder: str = Field(..., description="e.g. [[IMAGE_1]]")
    filename: str = Field(..., description="Save under images/, e.g. qkv_flow.png")
    alt: str
    caption: str = Field(description="Caption for the image.")
    prompt: str = Field(..., description="Prompt to send to the image model.")
    size: Literal["1024x1024", "1024x1536", "1536x1024"] = Field(
        default = "1024x1024", 
        description="pixel size of the image."
    )
    quality: Literal["low", "medium", "high"] = Field(
        default = "medium",
        description="image quality"
    )

class GlobalImagePlan(BaseModel):
    md_with_placeholders: str
    images: List[ImageSpec] = Field(default_factory=list)

