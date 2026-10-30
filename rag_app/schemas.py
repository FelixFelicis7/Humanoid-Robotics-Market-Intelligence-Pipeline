"""API contract: what /ask accepts and returns.

These pydantic models are separate from the dataclasses in rag.py on purpose:
rag.py can change its internals while the API format that clients rely on stays stable.
FastAPI uses these models to validate requests and to build the /docs page.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

# Must match company_type values in silver.company
CompanyType = Literal["humanoid_maker", "tier1", "investor",
                      "customer", "technology_partner", "other"]


# ---------------------------------------------------------------------------
# Request
# ---------------------------------------------------------------------------
class AskRequest(BaseModel):
    """Body of POST /ask. Only `question` is required; empty filters mean no filtering."""

    question: str = Field(..., min_length=1, max_length=1000,
                          examples=["Which tier-1 suppliers partnered with humanoid makers?"])
    top_k: int = Field(5, ge=1, le=20, description="number of chunks to retrieve")
    company_id: str | None = Field(None, examples=["schaeffler"],
                                   description="only documents involving this company")
    company_type: CompanyType | None = Field(None, examples=["tier1"],
                                             description="only documents involving this type of company")
    year_from: int | None = Field(None, ge=2000, le=2100, examples=[2025])
    source_types: list[str] | None = Field(None, examples=[["press_release", "news"]])

    @field_validator("question")
    @classmethod
    def question_not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("question must not be blank")
        return v

    @field_validator("company_id")
    @classmethod
    def normalise_company_id(cls, v: str | None) -> str | None:
        # company_id values are lowercase in silver.company; treat "" as no filter
        v = (v or "").strip().lower()
        return v or None

    @field_validator("source_types")
    @classmethod
    def drop_empty_source_types(cls, v: list[str] | None) -> list[str] | None:
        cleaned = [s.strip() for s in (v or []) if s.strip()]
        return cleaned or None


# ---------------------------------------------------------------------------
# Response
# ---------------------------------------------------------------------------
class SourceOut(BaseModel):
    """One cited document; `number` matches the [1], [2] markers in the answer."""
    number: int
    doc_id: str
    title: str
    url: str
    publisher: str
    publish_date: str
    translated_from_chinese: bool


class ChunkOut(BaseModel):
    """One retrieved chunk (shown in the UI as 'retrieved context')."""
    chunk_id: str
    doc_id: str
    title: str
    publish_date: str
    companies_info: str
    score: float
    chunk_text: str


class AskResponse(BaseModel):
    question: str
    answer: str
    sources: list[SourceOut]
    chunks: list[ChunkOut]


# ---------------------------------------------------------------------------
# Filter options (GET /filters)
# ---------------------------------------------------------------------------
class CompanyOption(BaseModel):
    company_id: str
    company_name: str
    company_type: str | None = None


class FilterOptions(BaseModel):
    """Values the UI can offer in its filters, taken from the data itself."""
    companies: list[CompanyOption]
    company_types: list[str]
    source_types: list[str]
    years: list[int]
