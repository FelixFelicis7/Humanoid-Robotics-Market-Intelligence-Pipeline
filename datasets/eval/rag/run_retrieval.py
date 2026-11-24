"""Retrieval evaluation: retrieval only, no LLM call.

Scores how well each retrieval configuration finds the expected documents of
questions.csv. Uses the production functions in rag_app/rag.py (search_index and
select_chunks), so the numbers describe the code that actually serves answers.

Run from the repo root:
    uv run python datasets/eval/rag/run_retrieval.py --config A
    uv run python datasets/eval/rag/run_retrieval.py --config B --cap 2
    uv run python datasets/eval/rag/run_retrieval.py --config C
    uv run python datasets/eval/rag/run_retrieval.py --config all     # A, B cap 1, B cap 2, C, C cap 2

Configurations
    A  vector search (ANN), keep the top k chunks                      (current default)
    B  vector search, at most --cap chunks per document, then top k
    C  hybrid search (vector + keyword); add --cap to also cap per document

Each question is searched once per query type for --pool chunks (default 30).
Every k (3, 5, 10, 15) is then cut from that pool locally.

Metrics are per DOCUMENT, not per chunk. The k chunks a configuration keeps are
turned into a list of distinct documents (order of first appearance).
Two kinds of relevant documents come from questions.csv:
    expected_doc_ids    must be found: they carry the answer (recall is measured on these)
    acceptable_doc_ids  also relevant (repeat or part of the answer); finding one counts
                        as a hit, missing one is not penalised
Metrics:
    hit@k     1 if at least one expected OR acceptable document is among them, else 0
    recall@k  share of the EXPECTED documents that are among them
    MRR       1 / rank of the first expected or acceptable document in the whole pool
Questions with should_refuse = Y have no expected documents and are not scored.

Outputs (never overwritten, the file name carries the run time):
    results/retrieval_<YYYYMMDD_HHMM>_<config>.csv   one row per question
    results/retrieval_<YYYYMMDD_HHMM>_raw.jsonl      the raw pools, for re-scoring offline
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
sys.path.insert(0, str(REPO_ROOT))

from rag_app.rag import Chunk, search_index, select_chunks  # noqa: E402

KS = [3, 5, 10, 15]
CATEGORY_ORDER = ["single_fact", "multi_doc", "same_event", "multi_company", "zh_source", "filtered"]

# name -> (query_type, max_chunks_per_doc)
ALL_CONFIGS = {
    "A": ("ANN", None),
    "B_cap1": ("ANN", 1),
    "B_cap2": ("ANN", 2),
    "C": ("HYBRID", None),
    "C_cap2": ("HYBRID", 2),
}


def load_questions(path: Path) -> list[dict]:
    with open(path, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        row["expected"] = row["expected_doc_ids"].split()
        row["acceptable"] = row.get("acceptable_doc_ids", "").split()
        row["filter_args"] = filter_args(row.get("filters", ""))
    return rows


def filter_args(filters_json: str) -> dict:
    """filters column -> keyword arguments of rag.search_index / rag.answer_question."""
    if not filters_json.strip():
        return {}
    filters = json.loads(filters_json)
    allowed = {"company_id", "company_type", "year_from", "source_types"}
    unknown = set(filters) - allowed
    if unknown:
        raise ValueError(f"unknown filter keys {sorted(unknown)}; allowed: {sorted(allowed)}")
    return filters


def distinct_docs(chunks: list[Chunk]) -> list[str]:
    """Documents in order of first appearance."""
    docs: list[str] = []
    for chunk in chunks:
        if chunk.doc_id not in docs:
            docs.append(chunk.doc_id)
    return docs


def score_question(pool: list[Chunk], expected: list[str], acceptable: list[str],
                   cap: int | None) -> dict:
    """Metrics for one question under one configuration, for every k.
    hit and MRR accept expected or acceptable documents; recall counts expected only."""
    relevant = set(expected) | set(acceptable)
    out: dict = {}
    for k in KS:
        docs = distinct_docs(select_chunks(pool, k, cap))
        found = [d for d in expected if d in docs]
        out[f"docs@{k}"] = " ".join(docs)
        out[f"hit@{k}"] = int(any(d in relevant for d in docs))
        out[f"recall@{k}"] = round(len(found) / len(expected), 4)
        out[f"missed@{k}"] = " ".join(d for d in expected if d not in docs)
        out[f"acceptable_found@{k}"] = " ".join(d for d in acceptable if d in docs)
    ranking = distinct_docs(pool)
    first = next((i + 1 for i, d in enumerate(ranking) if d in relevant), None)
    out["first_correct_rank"] = first or ""
    out["mrr"] = round(1 / first, 4) if first else 0.0
    out["not_in_pool"] = " ".join(d for d in expected if d not in ranking)
    return out


def shown(path: Path) -> str:
    """Path relative to the repo when it is inside it, else the full path."""
    path = path.resolve()
    return str(path.relative_to(REPO_ROOT)) if path.is_relative_to(REPO_ROOT) else str(path)


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def print_summary(name: str, rows: list[dict]) -> None:
    scored = [r for r in rows if r["scored"] == "Y"]
    groups = [("ALL", scored)]
    for cat in CATEGORY_ORDER + sorted({r["category"] for r in scored} - set(CATEGORY_ORDER)):
        members = [r for r in scored if r["category"] == cat]
        if members:
            groups.append((cat, members))

    print(f"\n=== {name}  ({len(scored)} scored questions) ===")
    header = f"{'category':<14}{'n':>3}  " + "  ".join(f"hit@{k:<2} rec@{k:<2}" for k in KS) + "   MRR"
    print(header)
    for label, members in groups:
        cells = "  ".join(
            f"{mean([m[f'hit@{k}'] for m in members]):>6.2f} {mean([m[f'recall@{k}'] for m in members]):>6.2f}"
            for k in KS)
        print(f"{label:<14}{len(members):>3}  {cells}  {mean([m['mrr'] for m in members]):>5.2f}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Score retrieval configurations against questions.csv")
    parser.add_argument("--config", choices=["A", "B", "C", "all"], default="A")
    parser.add_argument("--cap", type=int, help="max chunks per document (required for B, optional for C)")
    parser.add_argument("--pool", type=int, default=30, help="chunks fetched per question and query type")
    parser.add_argument("--questions", type=Path, default=HERE / "questions.csv")
    parser.add_argument("--out-dir", type=Path, default=HERE / "results")
    args = parser.parse_args()

    if args.config == "all":
        configs = dict(ALL_CONFIGS)
    elif args.config == "A":
        configs = {"A": ("ANN", None)}
    elif args.config == "B":
        cap = args.cap or 2
        configs = {f"B_cap{cap}": ("ANN", cap)}
    else:
        configs = {f"C_cap{args.cap}" if args.cap else "C": ("HYBRID", args.cap)}

    questions = load_questions(args.questions)
    stamp = datetime.now().strftime("%Y%m%d_%H%M")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    # One search per question and query type; every configuration is cut from these pools.
    pools: dict[tuple[str, str], list[Chunk]] = {}
    query_types = sorted({qt for qt, _ in configs.values()})
    raw_path = args.out_dir / f"retrieval_{stamp}_raw.jsonl"
    with open(raw_path, "w", encoding="utf-8") as raw:
        for q in questions:
            for qt in query_types:
                pool = search_index(q["question"], args.pool, query_type=qt, **q["filter_args"])
                pools[(q["question_id"], qt)] = pool
                raw.write(json.dumps({
                    "question_id": q["question_id"], "query_type": qt, "filters": q["filter_args"],
                    "chunks": [{"chunk_id": c.chunk_id, "doc_id": c.doc_id, "score": c.score} for c in pool],
                }) + "\n")
            print(f"searched {q['question_id']}", file=sys.stderr)

    for name, (qt, cap) in configs.items():
        rows = []
        for q in questions:
            pool = pools[(q["question_id"], qt)]
            row = {
                "question_id": q["question_id"], "category": q["category"], "config": name,
                "query_type": qt, "max_chunks_per_doc": cap or "", "filters": q.get("filters", ""),
                "expected_doc_ids": q["expected_doc_ids"], "n_expected": len(q["expected"]),
                "acceptable_doc_ids": q.get("acceptable_doc_ids", ""),
                "scored": "Y" if q["expected"] else "N",
            }
            if q["expected"]:
                row.update(score_question(pool, q["expected"], q["acceptable"], cap))
            else:   # refusal question: keep what was retrieved, for the generation analysis
                for k in KS:
                    row[f"docs@{k}"] = " ".join(distinct_docs(select_chunks(pool, k, cap)))
            row["top_score"] = round(pool[0].score, 4) if pool else ""
            rows.append(row)

        fields = list(dict.fromkeys(key for r in rows for key in r))
        out_path = args.out_dir / f"retrieval_{stamp}_{name}.csv"
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        print_summary(f"{name}  [{qt}, cap={cap}]", rows)
        print(f"-> {shown(out_path)}")
    print(f"\nraw pools -> {shown(raw_path)}")


if __name__ == "__main__":
    main()
