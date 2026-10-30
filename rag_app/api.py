"""HTTP API around the RAG pipeline.

Run from the repo root:
    uv run uvicorn rag_app.api:app --reload
Then open http://localhost:8000/docs to try it in the browser.

This file does no retrieval or generation itself: it validates the request,
calls rag.answer_question(), and converts the result into the API format.
"""

from __future__ import annotations

import logging
from dataclasses import asdict

from fastapi import FastAPI, HTTPException

from rag_app.filter_options import get_filter_options
from rag_app.rag import answer_question
from rag_app.schemas import AskRequest, AskResponse, ChunkOut, FilterOptions, SourceOut

logger = logging.getLogger("rag_app.api")

app = FastAPI(
    title="Humanoid Robotics RAG API",
    description="Ask questions about humanoid robotics industry documents; "
                "answers cite their sources.",
    version="0.1.0",
)


@app.get("/health")
def health() -> dict:
    """Is the API running? (Does not call Databricks.)"""
    return {"status": "ok"}


@app.get("/filters", response_model=FilterOptions)
def filters() -> FilterOptions:
    """Companies, source types and years for the UI filters.
    Read from Databricks tables once, then cached until the API restarts."""
    try:
        return FilterOptions.model_validate(get_filter_options())
    except Exception as exc:
        logger.exception("Reading filter options failed")
        raise HTTPException(status_code=502, detail=f"Could not read filter options: {exc}") from exc


# A plain `def` (not `async def`): the Databricks SDK calls are blocking,
# so FastAPI runs this in a worker thread and other requests are not held up.
@app.post("/ask", response_model=AskResponse)
def ask(req: AskRequest) -> AskResponse:
    try:
        result = answer_question(
            question=req.question,
            top_k=req.top_k,
            company_id=req.company_id,
            year_from=req.year_from,
            source_types=req.source_types,
            company_type=req.company_type,
        )
    except Exception as exc:
        # e.g. endpoint stopped, index not ready, not logged in to Databricks
        logger.exception("RAG pipeline failed")
        raise HTTPException(status_code=502, detail=f"RAG pipeline failed: {exc}") from exc

    # dataclass (internal) -> pydantic (API format); fields not in the model are dropped
    return AskResponse(
        question=result.question,
        answer=result.answer,
        sources=[SourceOut.model_validate(asdict(s)) for s in result.sources],
        chunks=[ChunkOut.model_validate(asdict(c)) for c in result.chunks],
    )
