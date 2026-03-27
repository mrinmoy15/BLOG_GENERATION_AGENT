from typing import TypedDict, Literal, List, Annotated, Tuple
from pydantic_models import EvidenceItem, Plan, ImageSpec
import operator

class State(TypedDict):
    topic: str

    # routing / research
    mode: Literal["closed_book", "hybrid", "open_book"]
    needs_research: bool
    queries: List[str]
    evidence: List[EvidenceItem]
    plan: Plan | None

    # recency
    as_of: str
    recency_days: int

    # worker
    sections: Annotated[List[Tuple[int, str]], operator.add]

    # reducer/image
    merged_md: str
    md_with_placeholders: str
    image_specs: List[ImageSpec]

    final: str