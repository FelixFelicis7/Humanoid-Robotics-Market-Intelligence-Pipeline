"""RAG core: retrieve -> build prompt -> generate -> format citations.

Runs on your machine and calls Databricks remotely (vector index + LLM endpoint).
Authentication comes from ~/.databrickscfg (created by `databricks auth login`).

Quick test from the repo root:
    python -m rag_app.rag "Which tier-1 suppliers partnered with humanoid makers?"
    python -m rag_app.rag "What did Schaeffler announce?" --company schaeffler --year-from 2025
    python -m rag_app.rag "Which tier-1 suppliers partnered with humanoid makers?" --company-type tier1
"""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass, field
from functools import lru_cache

from databricks.sdk import WorkspaceClient

# ---------------------------------------------------------------------------
# Config (override with environment variables if needed)
# ---------------------------------------------------------------------------
INDEX_NAME   = os.getenv("RAG_INDEX_NAME", "humanoid_robotics.silver.doc_chunks_index")
LLM_ENDPOINT = os.getenv("RAG_LLM_ENDPOINT", "databricks-gpt-oss-120b")
DEFAULT_TOP_K = 5

# Columns returned by the index (must be in columns_to_sync of 01_vector_index)
RETURN_COLUMNS = [
    "chunk_id", "doc_id", "chunk_text", "title", "url", "publisher",
    "source_type", "language", "publish_date", "publish_year",
    "company_ids", "company_types", "companies_info",
]

# company_type values in silver.company, explained to the LLM
COMPANY_TYPE_MEANINGS = {
    "humanoid_maker": "humanoid robot maker",
    "tier1": "automotive tier-1 supplier",
    "investor": "investor",
    "customer": "customer",
    "technology_partner": "technology partner",
    "other": "other",
}

NO_ANSWER = "I couldn't find this in the indexed documents."


# ---------------------------------------------------------------------------
# Data shapes
# ---------------------------------------------------------------------------
@dataclass
class Chunk:
    """One retrieved chunk plus the metadata copied onto it in doc_chunks."""
    chunk_id: str
    doc_id: str
    chunk_text: str
    title: str
    url: str
    publisher: str
    source_type: str
    language: str
    publish_date: str
    publish_year: int | None
    company_ids: list[str]
    company_types: list[str]
    companies_info: str       # "Humanoid (humanoid_maker); Schaeffler (tier1)"
    score: float


@dataclass
class Source:
    """One cited document, as shown to the user."""
    number: int               # [1], [2], ... in the answer
    doc_id: str
    title: str
    url: str
    publisher: str
    publish_date: str
    translated_from_chinese: bool


@dataclass
class RagAnswer:
    question: str
    answer: str                               # with [1], [2] markers
    sources: list[Source] = field(default_factory=list)
    chunks: list[Chunk] = field(default_factory=list)   # everything retrieved (for debugging/eval)
    raw_answer: str = ""                      # LLM output before citation formatting


# ---------------------------------------------------------------------------
# Databricks connection
# ---------------------------------------------------------------------------
@lru_cache(maxsize=1)
def get_client() -> WorkspaceClient:
    """Created once and reused. Reads the DEFAULT profile in ~/.databrickscfg
    (set DATABRICKS_CONFIG_PROFILE to use another one)."""
    return WorkspaceClient()


# ---------------------------------------------------------------------------
# 1. Retrieve
# ---------------------------------------------------------------------------
def build_filters(company_id: str | None = None,
                  year_from: int | None = None,
                  source_types: list[str] | None = None,
                  company_type: str | None = None) -> dict:
    """Translate user choices into the filter dict of a STANDARD Vector Search endpoint."""
    filters: dict = {}
    if company_id:
        # company_ids is space-separated ("agility schaeffler"); LIKE matches whole words
        filters["company_ids LIKE"] = company_id
    if company_type:
        # same idea: company_types = "humanoid_maker tier1"
        filters["company_types LIKE"] = company_type
    if year_from:
        filters["publish_year >="] = int(year_from)
    if source_types:
        filters["source_type"] = list(source_types)      # list = match any
    return filters


def _to_int(value) -> int | None:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def retrieve(question: str,
             top_k: int = DEFAULT_TOP_K,
             company_id: str | None = None,
             year_from: int | None = None,
             source_types: list[str] | None = None,
             company_type: str | None = None) -> list[Chunk]:
    """Ask the vector index for the top_k chunks closest to the question.
    The index embeds the question with the same model used for the chunks."""
    filters = build_filters(company_id, year_from, source_types, company_type)

    response = get_client().vector_search_indexes.query_index(
        index_name=INDEX_NAME,
        columns=RETURN_COLUMNS,
        query_text=question,
        num_results=top_k,
        filters_json=json.dumps(filters) if filters else None,
    )

    # Response is a table: column names in the manifest, rows in data_array.
    # The similarity score is added as the last column.
    column_names = [c.name for c in response.manifest.columns]
    rows = (response.result.data_array or []) if response.result else []

    chunks = []
    for row in rows:
        r = dict(zip(column_names, row))
        chunk = Chunk(
            chunk_id=r["chunk_id"],
            doc_id=r["doc_id"],
            chunk_text=r.get("chunk_text") or "",
            title=r.get("title") or "",
            url=r.get("url") or "",
            publisher=r.get("publisher") or "",
            source_type=r.get("source_type") or "",
            language=r.get("language") or "",
            publish_date=str(r.get("publish_date") or ""),
            publish_year=_to_int(r.get("publish_year")),
            company_ids=(r.get("company_ids") or "").split(),
            company_types=(r.get("company_types") or "").split(),
            companies_info=r.get("companies_info") or "",
            score=float(r.get("score") or 0.0),
        )
        # Safety net: make sure the filters really matched whole words
        if company_id and company_id not in chunk.company_ids:
            continue
        if company_type and company_type not in chunk.company_types:
            continue
        chunks.append(chunk)
    return chunks


# ---------------------------------------------------------------------------
# 2. Generate
# ---------------------------------------------------------------------------
_TYPE_LIST = "\n".join(f"  - {k}: {v}" for k, v in COMPANY_TYPE_MEANINGS.items())

SYSTEM_PROMPT = f"""You are an analyst answering questions about the humanoid robotics industry.

Each source starts with a header and a "Companies" line listing the companies involved
and their company type. Company types:
{_TYPE_LIST}

Rules:
- Use ONLY the sources provided by the user. Do not use outside knowledge.
- When you say what kind of company something is (e.g. "tier-1 supplier"),
  use only the "Companies" line. If a company is not listed there, do not label it.
- After every claim, cite the source id in square brackets, e.g. [D0004].
  Cite several sources like [D0004][D0001]. Only use ids that appear in the sources.
  Never mention source ids anywhere else in the text.
- Mention dates when describing announcements, deals or funding.
- If the sources do not contain the answer, reply exactly: "{NO_ANSWER}"
- Answer in English, concisely (a short paragraph or a few bullet points)."""


def build_prompt(question: str, chunks: list[Chunk]) -> list[dict]:
    """Group chunks by document and label each document with its doc_id."""
    by_doc: dict[str, list[Chunk]] = {}
    for c in chunks:                       # keeps retrieval order (best first)
        by_doc.setdefault(c.doc_id, []).append(c)

    blocks = []
    for doc_id, doc_chunks in by_doc.items():
        first = doc_chunks[0]
        note = ", translated from Chinese" if first.language == "zh" else ""
        header = (f"[{doc_id}] {first.title} "
                  f"({first.publisher}, {first.publish_date}, {first.source_type}{note})")
        companies = f"Companies: {first.companies_info or 'not recorded'}"
        body = "\n...\n".join(c.chunk_text for c in doc_chunks)
        blocks.append(f"{header}\n{companies}\n{body}")

    user_message = "Sources:\n\n" + "\n\n---\n\n".join(blocks) + f"\n\nQuestion: {question}"
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_message},
    ]


def _message_text(content) -> str:
    """gpt-oss can return content as a list of parts (reasoning + text); keep the text."""
    if isinstance(content, str):
        return content
    parts = []
    for part in content or []:
        if isinstance(part, dict):
            if part.get("type") == "text":
                parts.append(part.get("text", ""))
        elif getattr(part, "type", None) == "text":
            parts.append(getattr(part, "text", ""))
    return "".join(parts)


def generate(messages: list[dict]) -> str:
    """Call the LLM serving endpoint (chat format) through the same Databricks client."""
    response = get_client().api_client.do(
        "POST",
        f"/serving-endpoints/{LLM_ENDPOINT}/invocations",
        body={"messages": messages, "temperature": 0.0, "max_tokens": 1500},
    )
    return _message_text(response["choices"][0]["message"]["content"]).strip()


# ---------------------------------------------------------------------------
# 3. Citations
# ---------------------------------------------------------------------------
_BRACKET = re.compile(r"\[([^\[\]]*\bD\d{3,}\b[^\[\]]*)\]")   # [D0004] or [D0004, D0001]
_DOC_ID = re.compile(r"\bD\d{3,}\b")


def format_citations(raw_answer: str, chunks: list[Chunk]) -> tuple[str, list[Source]]:
    """Replace [doc_id] with [1], [2] in order of first appearance.
    Drop ids that were not retrieved (made up by the LLM). Only cited docs become sources."""
    docs = {}
    for c in chunks:
        docs.setdefault(c.doc_id, c)       # first chunk carries the document metadata

    numbers: dict[str, int] = {}

    def replace(match: re.Match) -> str:
        marks = []
        for doc_id in _DOC_ID.findall(match.group(1)):
            if doc_id not in docs:
                continue                    # hallucinated id -> remove
            if doc_id not in numbers:
                numbers[doc_id] = len(numbers) + 1
            mark = f"[{numbers[doc_id]}]"
            if mark not in marks:
                marks.append(mark)
        return "".join(marks)

    # The LLM sometimes writes full-width brackets 【D0004】 or ［D0004］; normalise to [ ]
    normalised = raw_answer.translate(str.maketrans({"【": "[", "】": "]", "［": "[", "］": "]"}))
    # Drop ids written in the prose, e.g. "with Humanoid (D0004)" -> "with Humanoid"
    normalised = re.sub(r"\s*\(\s*D\d{3,}(?:\s*[,;]\s*D\d{3,})*\s*\)", "", normalised)
    answer = _BRACKET.sub(replace, normalised)
    answer = re.sub(r"(\[\d+\])(?:\1)+", r"\1", answer)  # [2][2] -> [2]
    answer = re.sub(r"[ \t]+([.,;:])", r"\1", answer)   # tidy "text ." after removals
    answer = re.sub(r"[ \t]{2,}", " ", answer).strip()

    sources = [
        Source(
            number=n,
            doc_id=doc_id,
            title=docs[doc_id].title,
            url=docs[doc_id].url,
            publisher=docs[doc_id].publisher,
            publish_date=docs[doc_id].publish_date,
            translated_from_chinese=docs[doc_id].language == "zh",
        )
        for doc_id, n in numbers.items()
    ]
    return answer, sources


# ---------------------------------------------------------------------------
# Entry point used by the API
# ---------------------------------------------------------------------------
def answer_question(question: str,
                    top_k: int = DEFAULT_TOP_K,
                    company_id: str | None = None,
                    year_from: int | None = None,
                    source_types: list[str] | None = None,
                    company_type: str | None = None) -> RagAnswer:
    chunks = retrieve(question, top_k, company_id, year_from, source_types, company_type)
    if not chunks:
        return RagAnswer(question=question, answer=NO_ANSWER)

    raw = generate(build_prompt(question, chunks))
    answer, sources = format_citations(raw, chunks)
    return RagAnswer(question=question, answer=answer, sources=sources,
                     chunks=chunks, raw_answer=raw)


# ---------------------------------------------------------------------------
# Command-line test: python -m rag_app.rag "question" [options]
# ---------------------------------------------------------------------------
def _print_result(result: RagAnswer, show_chunks: bool) -> None:
    print("\n=== Answer ===\n")
    print(result.answer)

    if result.sources:
        print("\n=== Sources ===\n")
        for s in result.sources:
            note = " (translated from Chinese)" if s.translated_from_chinese else ""
            print(f"[{s.number}] {s.title}{note}")
            print(f"    {s.publisher}, {s.publish_date} | {s.doc_id}")
            print(f"    {s.url}")

    if show_chunks:
        print("\n=== Retrieved chunks ===\n")
        for c in result.chunks:
            print(f"{c.score:.3f}  {c.chunk_id}  {c.publish_date}  [{' '.join(c.company_ids)}]")
            print(f"       {c.title[:80]}")
            print(f"       Companies: {c.companies_info}")
        print("\n=== Raw LLM answer ===\n")
        print(result.raw_answer)


def main() -> None:
    parser = argparse.ArgumentParser(description="Ask the humanoid robotics RAG a question.")
    parser.add_argument("question")
    parser.add_argument("--top-k", type=int, default=DEFAULT_TOP_K)
    parser.add_argument("--company", help="one company_id, e.g. schaeffler")
    parser.add_argument("--company-type", choices=list(COMPANY_TYPE_MEANINGS),
                        help="only documents involving this type of company, e.g. tier1")
    parser.add_argument("--year-from", type=int)
    parser.add_argument("--source-type", action="append",
                        help="repeatable, e.g. --source-type press_release --source-type news")
    parser.add_argument("--show-chunks", action="store_true",
                        help="also print retrieved chunks and the raw LLM answer")
    args = parser.parse_args()

    result = answer_question(args.question, args.top_k, args.company,
                             args.year_from, args.source_type, args.company_type)
    _print_result(result, args.show_chunks)


if __name__ == "__main__":
    main()
