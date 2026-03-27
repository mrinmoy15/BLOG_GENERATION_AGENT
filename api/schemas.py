from pydantic import BaseModel, Field
from typing import Optional


class GenerateRequest(BaseModel):
    topic: str = Field(..., min_length=5, description="Blog topic to generate")
    model: str = Field(default="gpt-4o", description="LLM model to use")
    output_dir: str = Field(default="outputs", description="Directory to save output files")


class GenerateResponse(BaseModel):
    status: str
    filename: str
    final_md: str


class HealthResponse(BaseModel):
    status: str
    version: str = "1.0.0"
