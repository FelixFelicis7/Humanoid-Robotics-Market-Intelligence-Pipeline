# Design Decisions

This document records the main design decisions, why they were made, and what they
cost. Each entry follows the same structure:

- **Context**: the problem or constraint
- **Decision**: what was chosen
- **Alternatives**: what else was considered
- **Consequences**: benefits, costs and follow-ups

Status values: *Accepted* (in use), *Deferred* (decided, not yet implemented),
*Superseded* (replaced by a later decision; the old entry is kept).

| # | Decision | Area | Status |
|---|---|---|---|
| 1 | Collect documents locally, upload to a landing Volume | Ingestion | Accepted |
| 2 | Strict layer responsibilities; joins start in silver | Architecture | Accepted |
| 3 | All transformations in SQL, one file per table | Architecture | Accepted |
| 4 | AI results are append-only; parsing is rebuilt | AI extraction | Accepted |
| 5 | Rules go to SQL, not to the prompt | AI extraction | Accepted |
| 6 | Version prompts; finish the pipeline before prompt v2 | AI extraction | Accepted |
| 7 | One `dim_company` built from several curated CSVs | Data model | Accepted |
| 8 | Match company names with `upper(trim())`, no alias table yet | Data model | Accepted |
| 9 | Many-to-many via bridge tables; `role` lives on the bridge | Data model | Accepted |
| 10 | Placeholder dedup map fixes the interface | Data model | Accepted (dedup deferred) |
| 11 | Copy company metadata onto chunks | RAG | Accepted |
| 12 | Citations are handled in code, not trusted from the LLM | RAG | Accepted |
| 13 | Local app calls Databricks remotely; API separate from UI | RAG | Accepted |
| 14 | Source text never goes to GitHub | Governance | Accepted |

---

## 1. Collect documents locally, upload to a landing Volume

**Context.** Databricks Free Edition only allows outbound traffic to a small set of
trusted domains, so scraping news sites from a notebook is unreliable.

**Decision.** A local script (`scripts/fetch_docs.py`) downloads documents listed in
the manifest. Files are uploaded to `/Volumes/humanoid_robotics/landing/raw_docs/`
with the Databricks CLI. Databricks only processes files that are already in the
landing zone.

**Alternatives.** Scraping inside Databricks (blocked); a generic crawler (too much
work for ~150 documents, and not the focus of the project).

**Consequences.** Ingestion and processing are decoupled: the pipeline can be rerun
without touching the internet, and raw files stay unchanged. Collection is still
semi-manual; every document must be registered in the manifest first.

---

## 2. Strict layer responsibilities; joins start in silver

**Context.** Without clear rules, cleaning logic spreads across layers and
becomes hard to trace.

**Decision.**

| Layer | Responsibility | Allowed |
|---|---|---|
| landing | Raw files (Volume) | Files only |
| bronze | Raw data as tables | Technical metadata (`source_file`, `ingested_at`), BOM removal in column names. No joins, no type casting, no derived columns |
| silver | Transformation | Joins, casting, cleaning, standardization, AI extraction |
| gold | Data model | Facts, dimensions, bridges, metric views |

The manifest-to-text join happens in silver, because AI extraction (also silver)
needs `publish_date`, `language` and `doc_id`. Gold joins are model joins
(fact ↔ dimension).

**Alternatives.** Casting types in bronze (loses the original values if a cast
fails); joining in gold (AI extraction would have no document metadata).

**Consequences.** Any bronze table can be rebuilt from the files at any time.
Bronze tables are all strings, so every cast is explicit in silver.

---

## 3. All transformations in SQL, one file per table

**Context.** Phase 5 moves the transformations to dbt.

**Decision.** Silver and gold tables are written in SQL, one file per output table.
PySpark is used only where SQL is awkward: reading files, text cleaning
(`src_text_cleaning`) and chunking (`13_silver_doc_chunks`, LlamaIndex `SentenceSplitter`).

**Alternatives.** PySpark notebooks throughout.

**Consequences.** Each file maps directly to a future dbt model. Some text-processing
logic is less convenient in SQL.

---

## 4. AI results are append-only; parsing is rebuilt

**Context.** AI Function calls cost money and are limited by Free Edition fair usage.
Exceeding it stops compute for the day.

**Decision.**
- `silver.documents_extractions` (and `silver.doc_relevance`) are **append-only and
  never replaced**. Each row stores `ai_raw_json`, `ai_error`, `prompt_version`,
  `model_name`, `extracted_at`.
- Incremental processing uses `NOT EXISTS`: a document is skipped if a successful
  result for the same `doc_id` and `prompt_version` already exists. Failed calls are
  retried automatically on the next run.
- Everything downstream (`v_extractions_parsed`, `events_extracted`, …) is plain SQL
  and is rebuilt with `CREATE OR REPLACE`.

**Alternatives.** Re-extracting all documents on every run (expensive, results change
between runs); parsing inside the same statement as the AI call (a parsing fix would
require new AI calls).

**Consequences.** Changing parsing logic costs nothing. The raw results keep a full
history for comparing prompt versions. The extraction table must be protected from
full refreshes (in dbt: incremental model, full refresh disabled).

---

## 5. Rules go to SQL, not to the prompt

**Context.** LLMs are inconsistent with things a rule can do exactly.

**Decision.** The prompt asks only for what is explicitly in the text. SQL handles
the rest:
- Date fallback: `coalesce(try_to_date(event_date), publish_date)` plus a
  `date_is_publish_date` flag.
- `event_type` outside the allowed values → `other`.
- `currency` → `upper()`.
- `try_` functions on all AI output, so one bad value does not fail the whole table.

**Alternatives.** Asking the model to fill in dates and normalize values.

**Consequences.** Rules are deterministic, testable and free to change. The flag
makes it visible which dates are estimates.

---

## 6. Version prompts; finish the pipeline before prompt v2

**Context.** Pilot documents showed several extraction problems (see Known issues
in `CHANGELOG.md`).

**Decision.**
- Each prompt version is a separate file (`11_extract_v1.sql`, `11_extract_v2.sql`);
  old files are kept. The version is stored in the data and filtered in
  `v_extractions_parsed`.
- Problems are collected in `docs/prompt_issues.md` while the rest of the pipeline is
  built. Prompt v2 is written once, after a 30-document labelled baseline exists.
  Exception: issues that block downstream steps are fixed immediately.

**Alternatives.** Fixing the prompt after each problem is found.

**Consequences.** Fewer AI calls, and v2 can be shown to be better with numbers
instead of examples. Changing the version requires three synchronized edits (value
written, incremental condition, view filter); in dbt this becomes one variable.

---

## 7. One `dim_company` built from several curated CSVs

**Context.** The original list of 10 companies had two roles: the collection scope
and the company dimension. Events also mention investors, customers and partners
outside that list. Without them, bridge rows would have no `company_id`, counts by
`company_type` would miss them, and questions such as "who invested in Figure?"
could not be answered.

**Decision.**
- Three source CSVs: `company_maker.csv`, `company_tier1.csv` (focus companies) and
  `company_other.csv` (companies found in events and confirmed manually).
  `silver.company` is their `UNION ALL`; gold has one `dim_company`.
- `company_type` (what the company is: `humanoid_maker`, `tier1`, `investor`,
  `customer`, `technology_partner`, `other`) and `is_focus_company` (whether it is
  a research subject) are separate columns.
- New names from events go through a candidate query and manual review before being
  added; extraction errors are not added.

**Alternatives.** One dimension per company type (a bridge foreign key can only
point to one table, and a company can have several types); building the dimension
directly from extracted names (extraction errors would enter the model).

**Consequences.** Referential integrity holds for bridge tables. Focus companies with
no events yet still appear, which supports coverage checks. Each new batch of
documents needs a candidate review step, which stays outside the automated Job.

---

## 8. Match company names with `upper(trim())`, no alias table yet

**Context.** In the pilot data, the only name variants were differences in case.
Two names did not match because the standard name was too long
(`UBTech Robotics` vs `UBTech`, `Humanoid (SKL Robotics)` vs `Humanoid`).

**Decision.** Match on `upper(trim(name))`. Fix mismatches by changing
`company_name` to the short form used in news, **never `company_id`** (a stable key
referenced downstream). The original wording stays in `name_original`. The alias
table keeps its structure but is not used until real variants appear (for example
Chinese names or legal names such as "Robert Bosch GmbH").

**Alternatives.** Building an alias table from the start.

**Consequences.** The simplest rule that fits the data. Risk: "Humanoid" is also an
ordinary word, so false matches to `humanoid_uk` must be checked during manual
evaluation. Prompt v2 will list the standard names of focus companies.

---

## 9. Many-to-many via bridge tables; `role` lives on the bridge

**Context.** One event involves several companies, technologies and source documents.
The same company plays different roles in different events (Schaeffler appears as
investor, customer and partner).

**Decision.** Event attributes (date, amount) are stored once in `fct_events`.
`bridge_event_company` (with `role`), `bridge_event_technology` and
`bridge_event_source` hold the relationships. `role` describes the relationship, so
it is on the bridge, not on `dim_company`.

Counting rules, documented in table comments, the metric view and Genie
instructions:
- Event counts use `count(DISTINCT event_id)`.
- Funding amounts are counted once per event for the funded company:
  `event_type = 'funding' AND role IN ('target', 'issuer')`. Both values are needed
  because the model currently uses them inconsistently.

**Alternatives.** Repeating event attributes per company (amounts would be summed
several times); storing one role per company (wrong for most companies).

**Consequences.** The model answers both "how many" and "who with whom" questions,
at the cost of double-counting risk on joins, which is handled by the rules above.

---

## 10. Placeholder dedup map fixes the interface

**Context.** The same real event can be reported by several documents. With only
6 pilot documents, duplicates are rare.

**Decision.** `silver.event_dedup_map` maps `extracted_event_id → event_id`. In the
current placeholder, `event_id = extracted_event_id` and `n_sources = 1`. All gold
event tables take `event_id` through this map. The real rule is written but
deferred: same `event_type` + same set of `company_id`s + dates within 14 days →
same event, using gaps-and-islands.

**Alternatives.** Building gold without the map and adding it later (every gold
query would need to change).

**Consequences.** Deduplication can be added by changing one file; gold SQL stays
the same. Until then, counts can be too high (listed as a known limitation).

---

## 11. Copy company metadata onto chunks

**Context.** A vector index cannot join to other tables at query time, but users
want to filter by company and company type.

**Decision.** `doc_chunks` stores, per chunk:
- `company_ids`: companies from `event_companies` ∪ `primary_company`
  (space-separated, used for filters),
- `company_types`: their `company_type` (for filters),
- `companies_info`: e.g. `"Humanoid (humanoid_maker); Schaeffler (tier1)"`
  (put into the prompt so the LLM does not guess company types).

RAG uses `company_type` (what a company is), not `role` (what it did in one event).

**Alternatives.** Filtering after retrieval in Python (fewer relevant results
returned); a separate lookup at query time (an extra call per question).

**Consequences.** Filters work in a single index query. Company changes require
rebuilding `doc_chunks` and syncing the index; changes to the synced column list
require recreating the index. A filter means "the document mentions this company",
not "the document is about it".

---

## 12. Citations are handled in code, not trusted from the LLM

**Context.** The LLM sometimes uses full-width brackets, writes ids in other formats
or invents ids.

**Decision.** The prompt asks for `[doc_id]` after every claim. Code then normalizes
brackets, removes invalid or invented ids, renumbers citations as `[1]`, `[2]`, …,
lists only sources that were cited, and takes links from metadata. If retrieval
returns nothing, the LLM is not called and a fixed answer is returned (with a note if
filters may be too narrow).

**Alternatives.** Showing the LLM output as is.

**Consequences.** Every displayed source is a real retrieved document with a correct
link. Fewer wasted LLM calls. The code must be updated if the model's output format
changes.

---

## 13. Local app calls Databricks remotely; API separate from UI

**Context.** The data and models live in Databricks; the app is developed locally.

**Decision.** `rag_app/rag.py` calls Vector Search, the LLM serving endpoint and a SQL
warehouse through `databricks-sdk`. FastAPI (`api.py`) exposes the RAG logic;
Streamlit (`streamlit_app.py`) is only a client of the API.

**Alternatives.** Streamlit calling `rag.py` directly; a Databricks notebook UI.

**Consequences.** The RAG logic can be tested from the CLI, the API (`/docs`) or the
UI independently, and another front end could use the same API. Two processes must
run. Deployment to Databricks Apps (optional) needs service-principal permissions
for the index, LLM endpoint, warehouse and tables.

---

## 14. Source text never goes to GitHub

**Context.** Collected articles and filings are copyrighted.

**Decision.** Source text and PDFs stay in the private Volume. `data/raw/` is in
`.gitignore`, and notebooks are committed without outputs. GitHub contains code,
URLs, schemas, extracted fields and self-written summaries only.

**Consequences.** Others cannot rerun the pipeline exactly from the repository alone.
The README therefore relies on screenshots and a demo video to show results.
