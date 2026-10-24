# Extraction prompt changelog

Version history of the AI extraction prompt used by `ai_query` in `scripts/silver/05_silver_document_extraction.dbquery.ipynb` (`prompt_version` column of `silver.documents_extractions`). There is no standalone `sql/extract/` source folder in this repo today — the prompt and its JSON schema live inside that notebook; this file tracks what changed between versions and why, independent of where the SQL physically lives.

A new version is adopted only after it improves the targeted fields on the evaluation set without regressing other fields, per [`docs/business_rules.md`](../../docs/business_rules.md) rule **BR-AI-07**. Results of that comparison are recorded in [`docs/evaluation.md`](../../docs/evaluation.md).

---

## [v1] - 2026-10-18

### Added

Initial extraction prompt. Model: `databricks-gpt-oss-120b`, invoked via `ai_query(..., responseFormat => <strict JSON schema>, failOnError => false)`.

- Extracts a document-level `summary_en` (2-3 sentences, always in English) plus an array of `events` (0 to many per document).
- Per event: `event_type` (enum: `funding`, `partnership`, `product_launch`, `production_plan`, `policy`, `other`), `status` (enum: `announced`, `planned`, `completed`), `event_date` (explicit date only, else null), `companies[]` (each with `name`, `name_original`, `role`), `technology_areas[]`, `components[]` (free-text), `application_sector`, `region`, `amount`, `currency`, `quantity`, `quantity_unit`, `evidence_quote`.
- Hard extraction rules baked into the prompt text: only extract what's explicitly stated (null when unsure, never estimate); `event_date` may be resolved from relative wording using the document's `publish_date`, but only when the text gives a clear relative reference; `region` is where the event takes place, not where a company is headquartered; monetary amounts are returned as plain numbers with an ISO currency code; company names are returned in a standard English form (`name`) with the original script preserved separately (`name_original`); `evidence_quote` must be copied verbatim, never translated.
- Output is constrained by a `strict: true` JSON schema (`doc_events`), so malformed output fails the call (`ai_error`) rather than silently producing partial/invalid JSON.

## [v2] - Planned, not yet implemented

Scheduled prompt/schema changes, each tied to a specific rule in `docs/business_rules.md`:

- **BR-CO-09** — list the focus companies' standard names in the prompt and instruct the model to use them for `name`, keeping the original spelling in `name_original`. Goal: reduce the company-name matching gap tracked in `docs/prompt_issues.md`.
- **BR-ROLE-04** — add the role definitions from `docs/business_rules.md` §6 directly into the schema/prompt (what `target`, `issuer`, `investor`, `customer`, `supplier`, `partner` mean), to fix the `target`/`issuer` labeling inconsistency on funding recipients tracked as **BR-ROLE-03**.
- **BR-TECH-04** — restrict the free-text `components` field to concrete parts only (no product names, robot names, or technology-area labels); move product names currently leaking into `components` to a new `product_name` field.

None of these are implemented yet. `prompt_version` in `silver.documents_extractions` will move to `'v2'` once this version ships, and the adoption decision will be recorded here alongside the comparison results in `docs/evaluation.md`.
