"""
fetch_docs.py: download every document in the manifest (web page or PDF) and
save its body text as <file_name> (.txt).

Usage (run from the repo root):
    uv run python scripts/ingest/fetch_docs.py <manifest.csv> <output_dir>

In this project (datasets/raw/ is git-ignored, so raw text never reaches GitHub):
    uv run python scripts/ingest/fetch_docs.py datasets/manifest/manifest.csv datasets/raw

What it does:
  1. Read each manifest row (doc_id, url, file_name).
  2. If <output_dir>/<file_name> already exists, skip it (safe to rerun;
     skipped documents are not logged).
  3. If <output_dir>/pdf/<doc_id>.pdf already exists (e.g. downloaded by hand),
     extract text from it instead of downloading.
  4. Otherwise download the url and detect its type:
       - PDF  -> keep the original as pdf/<doc_id>.pdf, extract text page by page (pymupdf)
       - HTML -> keep the original as html/<doc_id>.html, extract the main text and drop
                 navigation and ads (trafilatura)
  5. APPEND one row per attempted document to <output_dir>/fetch_log.csv
     (earlier rows are kept).

When a document fails (the action_needed column in the log says what to do):
  - The site blocks scripts: open the url in a browser. For a web page, copy the
    body text into <file_name>; for a PDF, save it as pdf/<doc_id>.pdf. Then rerun.
  - Scanned PDF (images, no text layer): no text can be extracted; handle by hand.
"""
import csv
import sys
import time
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

import pymupdf
import requests
import trafilatura

MIN_CHARS = 300          # Shorter body text usually means extraction missed the article
HEADERS = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                         "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"}
LOG_COLUMNS = ["doc_id", "status", "file_type", "char_count", "action_needed", "run_date"]


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def is_pdf(url: str, content: bytes, content_type: str) -> bool:
    """Treat the response as a PDF if any of these holds: the url ends in .pdf,
    the server says it is a PDF, or the bytes start with %PDF.
    (Some PDF urls have no .pdf suffix, so the url alone is not enough.)"""
    return (urlparse(url).path.lower().endswith(".pdf")
            or "application/pdf" in content_type.lower()
            or content.startswith(b"%PDF"))


def download(url: str) -> tuple[str, bytes | str] | None:
    """Download url. Returns ("pdf", bytes) or ("html", text), or None on failure.
    requests goes first because PDF detection needs the raw bytes; if it fails,
    retry once with trafilatura's own downloader."""
    try:
        r = requests.get(url, headers=HEADERS, timeout=30)
        r.raise_for_status()
    except requests.RequestException as e:
        print(f"    requests failed: {e}; retrying with trafilatura")
        html = trafilatura.fetch_url(url)
        return ("html", html) if html else None

    if is_pdf(url, r.content, r.headers.get("Content-Type", "")):
        return "pdf", r.content
    r.encoding = r.apparent_encoding   # Chinese sites mix GBK and UTF-8; let requests detect it
    return "html", r.text


# ---------------------------------------------------------------------------
# Text extraction
# ---------------------------------------------------------------------------

def extract_html_text(html: str) -> str:
    """Main article text via trafilatura (navigation and ads removed). Empty string if none."""
    text = trafilatura.extract(html, include_comments=False, include_tables=True,
                               favor_recall=True)
    return (text or "").strip()


def extract_pdf_text(pdf_path: Path) -> str:
    """Text of every page via pymupdf, pages separated by a blank line.
    Empty string if the file cannot be opened or has no text layer."""
    try:
        with pymupdf.open(pdf_path) as doc:
            pages = [page.get_text().strip() for page in doc]
    except Exception as e:             # corrupt file, not actually a PDF, etc.
        print(f"    cannot open PDF: {e}")
        return ""
    return "\n\n".join(p for p in pages if p)


# ---------------------------------------------------------------------------
# One document
# ---------------------------------------------------------------------------

def fetch_one(doc_id: str, url: str, txt_path: Path, out: Path) -> list:
    """Process one document. Returns a log row [doc_id, status, file_type, char_count, action_needed]."""
    pdf_path = out / "pdf" / f"{doc_id}.pdf"
    manual_hint = (f"Handle by hand: web page -> copy the body text into {txt_path.name}; "
                   f"PDF -> save it as pdf/{doc_id}.pdf, then rerun")

    if pdf_path.exists():
        print("    using existing PDF (downloaded by hand or on an earlier run)")
        file_type, html = "pdf", None
    else:
        if not url:
            return [doc_id, "no_url", "", 0, manual_hint]
        result = download(url)
        time.sleep(1)                  # be polite: do not hammer the sites
        if result is None:
            return [doc_id, "download_failed", "", 0, manual_hint]
        file_type, data = result
        if file_type == "pdf":
            pdf_path.write_bytes(data)
            html = None
        else:
            html = data
            (out / "html" / f"{doc_id}.html").write_text(html, encoding="utf-8")

    text = extract_pdf_text(pdf_path) if file_type == "pdf" else extract_html_text(html)

    if len(text) < MIN_CHARS:
        hint = ("Probably a scanned PDF (no text layer); handle by hand" if file_type == "pdf"
                else "Body text too short; check html/ or copy the text by hand")
        return [doc_id, "too_short", file_type, len(text), hint]

    txt_path.write_text(text, encoding="utf-8")
    return [doc_id, "ok", file_type, len(text), ""]


# ---------------------------------------------------------------------------
# Log (append-only)
# ---------------------------------------------------------------------------

def append_log(log_path: Path, rows: list[list]) -> None:
    """Append this run's results to fetch_log.csv, keeping earlier rows.
    Logs written by the old script lack the file_type column: add it first
    (empty for old rows), then append."""
    if log_path.exists():
        with open(log_path, encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            old_columns, old_rows = reader.fieldnames, list(reader)
        if old_columns != LOG_COLUMNS:
            with open(log_path, "w", encoding="utf-8-sig", newline="") as f:
                w = csv.DictWriter(f, fieldnames=LOG_COLUMNS)
                w.writeheader()
                w.writerows({c: r.get(c, "") for c in LOG_COLUMNS} for r in old_rows)
    else:
        with open(log_path, "w", encoding="utf-8-sig", newline="") as f:
            csv.writer(f).writerow(LOG_COLUMNS)

    # Append as plain utf-8: a BOM may only appear at the very start of the file
    with open(log_path, "a", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        for r in rows:
            w.writerow(r + [date.today().isoformat()])


# ---------------------------------------------------------------------------

def main(manifest_path: str, out_dir: str) -> None:
    out = Path(out_dir)
    (out / "html").mkdir(parents=True, exist_ok=True)
    (out / "pdf").mkdir(parents=True, exist_ok=True)

    with open(manifest_path, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    log, n_skipped = [], 0
    for row in rows:
        doc_id = row["doc_id"].strip()
        url = (row.get("url") or "").strip()
        txt_path = out / row["file_name"].strip()
        print(f"[{doc_id}] {url}")

        if txt_path.exists():
            print("    already exists, skipped")
            n_skipped += 1
            continue

        entry = fetch_one(doc_id, url, txt_path, out)
        status, file_type, n = entry[1], entry[2], entry[3]
        print(f"    {status} ({file_type or '-'}, {n} chars)" + (f" -> {entry[4]}" if entry[4] else ""))
        log.append(entry)

    log_path = out / "fetch_log.csv"
    if log:
        append_log(log_path, log)

    n_ok = sum(1 for r in log if r[1] == "ok")
    print(f"\nThis run: {len(log)} processed, {n_ok} ok, {len(log) - n_ok} failed; "
          f"{n_skipped} skipped (already exist). Log: {log_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: uv run python scripts/ingest/fetch_docs.py <manifest.csv> <output_dir>")
    main(sys.argv[1], sys.argv[2])
