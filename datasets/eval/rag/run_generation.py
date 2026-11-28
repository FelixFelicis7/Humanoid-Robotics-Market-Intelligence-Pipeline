"""Generation evaluation: run the full RAG (retrieve + LLM) on every question.

Calls rag_app.rag.answer_question, the same function the API uses, and saves one
row per question for grading. Grading columns are left empty; they are filled
in a copy of the file. Rubric:
    citation_correct  Y / Partial / N   each cited claim is supported by the cited document
    fact_coverage     0-1               share of key_facts present in the answer
    refusal_correct   Y / N             refused when should_refuse = Y; answered otherwise
                                        (stating "not disclosed" with a citation also counts
                                        as a correct refusal, e.g. Q25)
    hallucination     Y / N             a number, company, date or claim not in the sources
    error_type        retrieval_miss, crowded_out, fact_omitted, wrong_citation,
                      hallucination, over_refusal, translation_error
Helper columns (computed, not graded):
    expected_missed   expected documents that were not retrieved -> a retrieval error,
                      not a generation error
    cited_unlisted    cited documents that are neither expected nor acceptable -> check them
The write-up of results goes into docs/evaluation.md (RAG section).

Run from the repo root:
    uv run python datasets/eval/rag/run_generation.py                      # rag.py defaults
    uv run python datasets/eval/rag/run_generation.py --top-k 10 --cap 2
    uv run python datasets/eval/rag/run_generation.py --only Q03,Q11 --tag rerun   # stability check

Output (never overwritten, the file name carries the run time):
    results/generation_<YYYYMMDD_HHMM>[_<tag>].csv
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT))

from rag_app import rag  # noqa: E402

GRADING_COLUMNS = ["citation_correct", "fact_coverage", "refusal_correct",
                   "hallucination", "error_type", "grader_notes"]


def filter_args(filters_json: str) -> dict:
    """filters column -> keyword arguments of rag.answer_question."""
    if not filters_json.strip():
        return {}
    filters = json.loads(filters_json)
    allowed = {"company_id", "company_type", "year_from", "source_types"}
    unknown = set(filters) - allowed
    if unknown:
        raise ValueError(f"unknown filter keys {sorted(unknown)}; allowed: {sorted(allowed)}")
    return filters


def distinct(items: list[str]) -> list[str]:
    return list(dict.fromkeys(items))


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the full RAG on questions.csv and save the answers")
    parser.add_argument("--top-k", type=int, default=rag.DEFAULT_TOP_K)
    parser.add_argument("--cap", type=int, default=rag.DEFAULT_MAX_CHUNKS_PER_DOC,
                        help="max chunks per document (default: rag.py default)")
    parser.add_argument("--query-type", choices=["ANN", "HYBRID"], default=rag.DEFAULT_QUERY_TYPE)
    parser.add_argument("--prompt-version", choices=sorted(rag.PROMPTS), default=rag.DEFAULT_PROMPT_VERSION,
                        help="system prompt version in rag.py (default: rag.py default)")
    parser.add_argument("--only", help="comma-separated question ids, e.g. Q03,Q11")
    parser.add_argument("--tag", help="suffix for the output file name, e.g. rerun or v2")
    parser.add_argument("--questions", type=Path, default=HERE / "questions.csv")
    parser.add_argument("--out-dir", type=Path, default=HERE / "results")
    args = parser.parse_args()

    with open(args.questions, newline="", encoding="utf-8-sig") as f:
        questions = list(csv.DictReader(f))
    if args.only:
        wanted = set(args.only.split(","))
        questions = [q for q in questions if q["question_id"] in wanted]

    rows = []
    for q in questions:
        started = time.time()
        try:
            result = rag.answer_question(q["question"], top_k=args.top_k,
                                         max_chunks_per_doc=args.cap, query_type=args.query_type,
                                         prompt_version=args.prompt_version,
                                         **filter_args(q.get("filters", "")))
            error = ""
        except Exception as exc:  # keep going: one failed call must not lose the whole run
            result = rag.RagAnswer(question=q["question"], answer="")
            error = f"{type(exc).__name__}: {exc}"

        expected = q["expected_doc_ids"].split()
        acceptable = q.get("acceptable_doc_ids", "").split()
        retrieved = distinct([c.doc_id for c in result.chunks])
        cited = [s.doc_id for s in result.sources]
        rows.append({
            "question_id": q["question_id"],
            "category": q["category"],
            "question": q["question"],
            "filters": q.get("filters", ""),
            "should_refuse": q["should_refuse"],
            "expected_doc_ids": q["expected_doc_ids"],
            "acceptable_doc_ids": q.get("acceptable_doc_ids", ""),
            "key_facts": q["key_facts"],
            "top_k": args.top_k,
            "max_chunks_per_doc": args.cap or "",
            "query_type": args.query_type,
            "prompt_version": args.prompt_version,
            "answer": result.answer,
            "raw_answer": result.raw_answer,
            "refused": "Y" if rag.is_no_answer(result.answer) else "N",
            "cited_doc_ids": " ".join(cited),
            "retrieved_doc_ids": " ".join(retrieved),
            "retrieved_chunk_ids": " ".join(c.chunk_id for c in result.chunks),
            "expected_retrieved": " ".join(d for d in expected if d in retrieved),
            "expected_missed": " ".join(d for d in expected if d not in retrieved),
            "acceptable_retrieved": " ".join(d for d in acceptable if d in retrieved),
            "cited_unlisted": " ".join(d for d in cited if d not in expected and d not in acceptable),
            "seconds": round(time.time() - started, 1),
            "run_error": error,
            **{col: "" for col in GRADING_COLUMNS},
        })
        print(f"{q['question_id']}  refused={rows[-1]['refused']}  cited={rows[-1]['cited_doc_ids'] or '-'}"
              f"{'  ERROR ' + error if error else ''}", file=sys.stderr)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M")
    out_path = args.out_dir / f"generation_{stamp}{'_' + args.tag if args.tag else ''}.csv"
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    refuse = [r for r in rows if r["should_refuse"] == "Y"]
    answerable = [r for r in rows if r["should_refuse"] != "Y"]
    print(f"\n{len(rows)} questions, top_k={args.top_k}, cap={args.cap}, query_type={args.query_type}, "
          f"prompt={args.prompt_version}")
    print(f"should refuse: {sum(r['refused'] == 'Y' for r in refuse)}/{len(refuse)} refused")
    print(f"should answer: {sum(r['refused'] == 'Y' for r in answerable)}/{len(answerable)} refused (over-refusal)")
    print(f"errors: {sum(bool(r['run_error']) for r in rows)}")
    print(f"-> {out_path}")


if __name__ == "__main__":
    main()
