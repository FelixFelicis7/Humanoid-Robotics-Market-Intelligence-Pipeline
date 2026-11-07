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

### Added
- `scripts/silver/sql/` and `scripts/gold/sql/`: plain `.sql` versions of the SQL
  steps (silver 04–12, gold 01–08 and 99), for Job "SQL file" tasks and the later
  move to dbt. Original notebooks and `.dbquery.ipynb` files are kept unchanged.
  Check queries were moved out of the build files into `12_silver_quality_check.sql`.

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

### Known issues (new)
- Embedding model `databricks-gte-large-en` is English-only; switch to a
  multilingual model before adding Chinese documents.

### Planned
- Databricks Job orchestrating bronze → silver → gold → chunks → vector index sync,
  exported as YAML to `orchestration/`.
- Expand the corpus from 6 to ≥100 documents (≥25% Chinese), loaded in batches.
- Evaluation: RAG question set (hit@k, citation accuracy) and a manually labelled
  30-document set for AI extraction (v1 baseline).

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

[Unreleased]: https://github.com/FelixFelicis7/Humanoid-Robotics-Market-Intelligence-Pipeline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/FelixFelicis7/Humanoid-Robotics-Market-Intelligence-Pipeline/releases/tag/v0.1.0
