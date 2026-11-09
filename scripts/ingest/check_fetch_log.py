"""
check_fetch_log.py: after running fetch_docs.py, check that every document in the
batch is ready to upload (read-only, changes no files).

Usage (run from the repo root; same arguments as fetch_docs.py):
    uv run python scripts/ingest/check_fetch_log.py <manifest.csv> <output_dir>
For example:
    uv run python scripts/ingest/check_fetch_log.py datasets/manifest/manifest.csv datasets/raw

What it does:
  1. For each manifest document: does the txt exist, how many characters, and what
     is the latest status in fetch_log.csv (a document can have several log rows;
     the last one wins).
  2. List documents that still need manual work (no txt, or fewer than 300 characters),
     with their action_needed hint.
  3. List txt files in <output_dir> that have no manifest row (a file_name mismatch
     means silver.documents cannot join the text after upload to Databricks).

Prints "All ready" on the last line when nothing is left to do.
"""
import csv
import sys
from pathlib import Path

MIN_CHARS = 300          # Keep in sync with fetch_docs.py


def read_csv(path: Path) -> list[dict]:
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def latest_log_by_doc(log_path: Path) -> dict[str, dict]:
    """Keep only the last log row per doc_id (the log is append-only, so later rows are newer)."""
    if not log_path.exists():
        return {}
    latest = {}
    for row in read_csv(log_path):
        latest[row["doc_id"].strip()] = row
    return latest


def check_documents(manifest: list[dict], out: Path, latest: dict) -> list[dict]:
    """One row per manifest document: doc_id, txt character count (None if missing),
    latest status, action_needed."""
    results = []
    for row in manifest:
        doc_id = row["doc_id"].strip()
        txt_path = out / row["file_name"].strip()
        n_chars = len(txt_path.read_text(encoding="utf-8").strip()) if txt_path.exists() else None
        log = latest.get(doc_id, {})
        results.append({
            "doc_id": doc_id,
            "file_name": txt_path.name,
            "n_chars": n_chars,
            "status": log.get("status", "(no log entry)"),
            "action_needed": log.get("action_needed", ""),
        })
    return results


def find_orphan_txt(manifest: list[dict], out: Path) -> list[str]:
    """txt files in <output_dir> that no manifest row points to."""
    expected = {row["file_name"].strip() for row in manifest}
    return sorted(p.name for p in out.glob("*.txt") if p.name not in expected)


def main(manifest_path: str, out_dir: str) -> None:
    out = Path(out_dir)
    manifest = read_csv(Path(manifest_path))
    results = check_documents(manifest, out, latest_log_by_doc(out / "fetch_log.csv"))

    ready = [r for r in results if r["n_chars"] is not None and r["n_chars"] >= MIN_CHARS]
    todo = [r for r in results if r not in ready]
    orphans = find_orphan_txt(manifest, out)

    print(f"Manifest has {len(results)} documents: {len(ready)} ready, {len(todo)} to do\n")

    if todo:
        print("To do (no txt, or txt shorter than 300 characters):")
        for r in todo:
            size = "no txt" if r["n_chars"] is None else f"txt has only {r['n_chars']} chars"
            print(f"  {r['doc_id']}  {size}  latest status: {r['status']}")
            if r["action_needed"]:
                print(f"         -> {r['action_needed']}")
        print()

    if orphans:
        print("txt files with no manifest row (check file_name for typos):")
        for name in orphans:
            print(f"  {name}")
        print()

    if not todo and not orphans:
        print("All ready. Upload: txt -> raw_docs, manifest.csv -> manifest")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: uv run python scripts/ingest/check_fetch_log.py <manifest.csv> <output_dir>")
    main(sys.argv[1], sys.argv[2])
