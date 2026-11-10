# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is `0.x`, table structures and interfaces may still change.

Two kinds of versions are tracked separately:

- **Project version** (this file, Git tags `vX.Y.Z`): what the pipeline as a whole can do.
- **Processing-logic versions** (stored as columns in the data): bumped only when the
  *output content* of a step changes for the same input.

| Logic | Column | Current | Where it is set |
|---|---|---|---|
| AI extraction prompt | `prompt_version` | `v1` | `05_silver_document_extraction`; filtered in `v_extractions_parsed` |
| Text cleaning | `cleaning_version` | `v2` | `src_text_cleaning` → `documents_clean` |
| Chunking | `chunking_version` | `v1` (512 tokens, 64 overlap) | `13_silver_doc_chunks` |

Adding metadata columns (for example to `doc_chunks`) is a schema change. It is
recorded here, but it does not bump `chunking_version`, because the chunk text and
`embedding_text` are unchanged.

---

## [Unreleased]

### Planned
- Test Chinese-language questions against the RAG app once Chinese documents are
  loaded. Switch to a multilingual embedding model only if Chinese questions are to
  be supported, or if translation option B (keep Chinese body text) is adopted.
- Expand the corpus to ~80–100 documents (≥25% Chinese, ≥8 per focus company), loaded
  in batches. Batch 1 done (26 documents).
- Evaluation: RAG question set (hit@k, citation accuracy) and a manually labelled
  30-document set for AI extraction (v1 baseline).
- Sync manifest and seeds to the Volume automatically. Bronze reads
  `manifest.csv` and the seed CSVs from `/Volumes/humanoid_robotics/landing/`, but a
  Git pull only updates the Git folder, so an edited CSV is silently ignored until it
  is uploaded by hand (batch 2 first ran on the old 26-row manifest). Options: read
  the CSVs from the Git folder in bronze, or add a first Job task that copies them
  from the Git folder to the Volume.

### Added
- `scripts/ingest/fetch_docs.py` (moved into the repo): downloads web pages and PDFs,
  keeps the original under `html/` or `pdf/`, uses a hand-downloaded `pdf/<doc_id>.pdf`
  if present, and appends to `fetch_log.csv` instead of overwriting it.
- `scripts/ingest/check_fetch_log.py`: read-only check that every manifest document
  has a txt before upload, and that no txt is missing from the manifest.
- Data expansion batch 1: D0007–D0026 (20 documents, 6 Chinese, first PDF filing).
- Data expansion batch 2: D0027–D0074 (48 documents, 6 Chinese), market-wide: North
  American, European, Chinese and Korean makers, AI platforms, component suppliers and
  national policy. 8 companies added to `company_seed.csv`.
- 24 companies in `company_other.csv` found in batch 1 (investors, customers, three
  humanoid makers) and the placeholder `undisclosed` for unnamed counterparties (BR-CO-10).
- `12_silver_quality_check.sql` Check 6: alias integrity (one company per name; every
  alias points to an existing company).

### Changed
- Manifest and company seeds moved to `datasets/manifest/` and `datasets/seeds/`;
  `datasets/raw/` (full text, HTML, PDF) is git-ignored.
- Alias table enabled (BR-CO-04): `09_silver_event_companies` and `07_company_candidates`
  match extracted names on `company_name` or an alias. The Job task `silver_09_event_companies`
  now also depends on `silver_02_company_alias`.
- `distinct_company_count` excludes the `undisclosed` placeholder.
- Government bodies are not added to the company table (BR-CO-11); they are on the
  ignored list of `12` Check 1.
- Original notebooks are now kept in sync with the `.sql` files the Job runs
  (design decision 16). Brought up to date: silver `06`, `07`, `09`, `10`, `11`, `12`,
  gold `01`, `metric_views.ipynb` (column rename, alias matching, missing checks).

### Fixed
- Silent AI failures could make a document drop out for good, with no error:
  - `05`: `concat()` returns NULL if any argument is NULL, so a missing `publish_date`,
    `language` or `primary_company` produced a NULL prompt. These fields now fall back to
    a default text. Prompts for documents with all fields filled are unchanged, so
    `prompt_version` stays `v1`.
  - `05` and `06`: a row with neither `ai_raw_json` nor `ai_error` no longer counts as a
    successful extraction, so the document is retried.
  - `04`: a document is skipped only if it already has a non-NULL label, so a failed
    classification is retried instead of excluding the document permanently.
- `12_silver_quality_check.sql` Check 7: lists silent failures (empty extractions,
  documents without a relevance label, unparseable JSON).

### Known issues
- `ai_translate` mistranslates some Chinese company names (PI-006); handled with aliases.
- Long multi-topic filings can be classified as not relevant (PI-005, D0010).

---

## [0.2.0] - 2026-11-08

The whole pipeline runs as one Databricks Job, and reruns do not repeat AI calls.

### Added
- Databricks Job `humanoid robotics dwh pipeline` (25 tasks): bronze → silver
  (translation, relevance, AI extraction) → gold star schema, constraints, comments,
  metric views, plus `doc_chunks` → vector index sync. Max concurrent runs = 1,
  no automatic retries on the AI tasks. Exported to
  `orchestration/humanoid_pipeline_job.yml` (Declarative Automation Bundles format).
  Verified: a second run with no new documents makes no new AI calls
  (translations, relevance and extraction row counts unchanged).
- `scripts/silver/sql/` and `scripts/gold/sql/`: plain `.sql` versions of the SQL
  steps (silver 04–12, gold 01–08 and 99), for Job "SQL file" tasks and the later
  move to dbt. Original notebooks and `.dbquery.ipynb` files are kept unchanged.
  Check queries were moved out of the build files into `12_silver_quality_check.sql`.
- `12_silver_quality_check.sql` Check 5: row counts and latest timestamps of the
  three AI tables, to compare before and after a Job run.

### Changed
- Manifest renamed from `manifest_pilot.csv` / `bronze.manifest_pilot` to
  `manifest.csv` / `bronze.manifest`, so new documents are added as rows in the
  same file and the Job does not need to change. Updated in `bronze_manifest` and
  `03_silver_documents`.
- Translation is now incremental. New append-only table
  `silver.document_translations` (`scripts/silver/sql/03a_silver_document_translations.sql`)
  translates each Chinese document once, keyed on `doc_id` + a SHA-256 hash of
  title, publisher and text. `03_silver_documents` joins it instead of calling
  `ai_translate` on every run, and fails if a Chinese document has no translation.
  New Job task `silver_03a_document_translations` runs before `silver_03_documents`.
- Renamed the imputed-date flag `publish_date` → `date_is_publish_date` in
  `silver.events_extracted`, `silver.event_dedup_map` and `gold.fct_events`
  (BR-DATE-06). The old name collided with the real `dim_source.publish_date`.
  Only the `.sql` versions were changed; the original notebooks are reference only.

### Fixed
- `02_silver_company_alias`: select `alias` and `company_id` explicitly. Bronze had
  gained `source_file` / `ingested_at`, which broke the overwrite with
  `DELTA_METADATA_MISMATCH` on the first Job run.
- `metric_views.sql`: `CREATE VIEW` → `CREATE OR REPLACE VIEW` so the Job can rerun,
  and removed `;` and `--` from the YAML inside `$$ ... $$`. Job "SQL file" tasks
  split statements on `;` without respecting `$$` blocks.
- `gold.dim_company` rebuilt from the trimmed `silver.company` (first Job run).

### Known issues
- Embedding model `databricks-gte-large-en` is English-only. This is fine as long as
  Chinese documents are fully translated before chunking (current design), but
  questions asked in Chinese will not retrieve well.
- `doc_chunks` is fully overwritten on each run, so every index sync re-embeds all
  chunks. Fine at 6 documents; switch to MERGE as the corpus grows.
- If a document's source text changes after extraction, it is retranslated but not
  re-extracted (extraction is incremental by `doc_id`).
- The original notebooks / `.dbquery.ipynb` files and the new `.sql` files contain
  the same logic. The Job runs the `.sql` files; the originals are reference only.

---

## [0.1.0] - 2026-11-03

First end-to-end run: landing → bronze → silver → gold → RAG, on 6 English pilot
documents (D0001–D0006).

### Added

**Ingestion (local → landing)**
- Unity Catalog structure: catalog `humanoid_robotics` with schemas `landing`,
  `bronze`, `silver`, `gold`; Volumes `raw_docs`, `manifest`, `seeds`.
- `scripts/fetch_docs.py`: reads the manifest CSV, extracts article text with
  `trafilatura`, skips already-downloaded files, writes `fetch_log.csv`.
- Document manifest as the master list of documents (`doc_id`, `url`, `source_type`,
  `language`, `publish_date`, `primary_company`, `in_eval_set`, …).

**Bronze**
- `bronze.raw_docs` (whole-text read of the folder), `bronze.manifest`,
  `bronze.company_seed` and related seed tables. Strings only, plus `source_file` /
  `ingested_at`; column-name BOM removed.

**Silver**
- `silver.company`: union of `company_maker`, `company_tier1`, `company_other` CSVs,
  with `company_type` and `is_focus_company`.
- `silver.company_alias`: structure only, not used yet.
- `silver.documents` (manifest LEFT JOIN raw text), `silver.documents_clean`.
- `silver.doc_relevance`: `ai_classify` relevance check, append-only.
- `silver.documents_extractions`: `ai_query` (`databricks-gpt-oss-120b`, JSON schema,
  `strict: true`) raw results, append-only, incremental via `NOT EXISTS`.
- `silver.v_extractions_parsed`, `silver.document_summaries`, `silver.events_extracted`,
  `silver.event_companies`.
- `silver.event_dedup_map`: placeholder (1 extracted event = 1 event) that fixes the
  interface for future deduplication.
- `silver.doc_chunks`: chunks from LlamaIndex `SentenceSplitter` (512 tokens, 64 overlap)
  with document and company metadata; Change Data Feed enabled.
- Quality-check queries (failed calls, parse failures, row reconciliation,
  evidence quote not found in source, amount/currency consistency).

**Gold**
- Star schema: `fct_events`, `dim_company`, `dim_source`, `dim_date`,
  `dim_technology`, `bridge_event_company`, `bridge_event_technology`,
  `bridge_event_source`.

**RAG**
- Vector Search endpoint `humanoid_vs_endpoint` and Delta Sync index
  `silver.doc_chunks_index` (`scripts/rag/01_vector_index`, with a
  `RECREATE_INDEX` switch); retrieval check notebook.
- `rag_app/rag.py`: retrieval → prompt → LLM → citation post-processing; CLI entry
  point.
- `rag_app/api.py` (FastAPI: `GET /health`, `GET /filters`, `POST /ask`),
  `schemas.py` (input validation), `filter_options.py` (filter values read through
  a SQL warehouse, cached per process).
- `rag_app/streamlit_app.py`: chat UI with sidebar filters (company, company type,
  year, source type), clickable sources and expandable chunks.
- Python environment managed with `uv` (`pyproject.toml`, `uv.lock`).

### Changed
- `doc_chunks`: added `company_types` (for filtering) and `companies_info`
  (for the prompt), taken from `silver.company.company_type`. The vector index was
  recreated, because `columns_to_sync` is fixed when the index is created.
- Company standard names shortened to the form most used in news
  (`UBTech Robotics` → `UBTech`, `Humanoid (SKL Robotics)` → `Humanoid`).
  `company_id` values are unchanged.
- LLM calls use `WorkspaceClient().api_client.do(POST /serving-endpoints/.../invocations)`
  instead of the deprecated `get_open_ai_client()`.

### Fixed
- `01_silver_companies`: trimming was applied to the raw DataFrame instead of the
  working one, so whitespace was not removed.
- RAG citations: full-width brackets `【】` normalized to `[]`; inline `(D0004)`
  references removed; citation ids not in the retrieved sources are dropped.

### Known issues
- No event deduplication: an event reported by several documents is counted
  several times.
- Inconsistent `role` for the funded company (`target` vs `issuer`). The funding
  measure therefore uses `role IN ('target', 'issuer')`. To be defined in prompt v2.
- `components` mixes product names and technology categories with real components;
  not used in the gold model.
- Many events have `technology_areas = not_specified`; not yet verified against
  the source text.
- D0005: "2.5亿" was translated as "2.5 billion yuan" (should be 250 million).
- `gold.dim_company` has not been rebuilt since the `silver.company` trim fix.
- RAG with `top_k = 5` misses relevant documents for broad questions (D0001, D0003
  ranked 7th–10th); default settings to be decided by evaluation.
- Only 6 English documents; results are not yet statistically meaningful.

[Unreleased]: https://github.com/FelixFelicis7/Humanoid-Robotics-Market-Intelligence-Pipeline/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/FelixFelicis7/Humanoid-Robotics-Market-Intelligence-Pipeline/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/FelixFelicis7/Humanoid-Robotics-Market-Intelligence-Pipeline/releases/tag/v0.1.0
