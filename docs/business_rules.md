# Business Rules Specification

**Humanoid Robotics Market Intelligence Pipeline**

| Field | Value |
|---|---|
| Document ID | BR-HRMI |
| Version | 0.1 (draft) |
| Status | Draft — pending review against pilot results and eval baseline |
| Owner | Project owner (data & analytics) |
| Last updated | 2026-10-24 |
| Applies to | Catalog `humanoid_robotics`: `silver`, `gold`, metric views, Genie space |
| Related docs | `docs/data_dictionary.md`, `docs/evaluation.md`, `docs/prompt_issues.md`, `genie/instructions.md`, `sql/extract/CHANGELOG.md` |

---

## 1. Purpose and scope

This document is the **single source of truth** for how business concepts in this project are defined and calculated. It answers two questions for every metric or term:

1. **What does it mean?** (business definition)
2. **Where is it enforced?** (the table, view, file or instruction that implements it)

**In scope:** event classification, company identification and roles, dates, amounts, counting rules, technology classification, AI extraction rules, data quality controls, and known limitations.

**Out of scope:** physical pipeline design (see README / design decisions), source collection procedures (see implementation plan §1.2–1.4).

### 1.1 How rules are enforced (order of preference)

A rule is implemented in the **lowest layer that can enforce it**. Prose instructions are the last resort, because only code is guaranteed to be applied.

| Priority | Layer | Example | Guarantee |
|---|---|---|---|
| 1 | Data (silver / gold SQL) | Out-of-range `event_type` → `other` | Always applied |
| 2 | Semantic layer (metric view YAML) | Funding amount counts only `event_type = 'funding'` | Applied whenever the metric view is used |
| 3 | Metadata (table / column comments) | Meaning and unit of `amount_usd` | Read by Genie and other AI tools; not enforced |
| 4 | Genie instructions (prose) | "Last year" = previous calendar year | A hint to the model; may be ignored |

### 1.2 Rule status values

| Status | Meaning |
|---|---|
| **Implemented** | Enforced in code today |
| **Planned** | Agreed; implementation scheduled (see roadmap) |
| **Proposed** | Draft; needs review or evidence before adoption |
| **To verify** | Believed true; must be checked against the current code |

### 1.3 Rule ID convention

`BR-<AREA>-<NN>`. IDs are never reused. A retired rule keeps its ID with status `Retired` and a change-log entry.

---

## 2. Analysis population (BR-SCOPE)

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-SCOPE-01 | The analysis population is the set of documents registered in the manifest. Results describe **these documents**, not the whole humanoid robotics market. | Manifest → `silver.documents`; `genie/instructions.md` | Implemented |
| BR-SCOPE-02 | Every document must be registered in the manifest (with a permanent `doc_id`, never reused) before it is downloaded or processed. | Manifest process; `silver.documents` (manifest LEFT JOIN raw text) | Implemented |
| BR-SCOPE-03 | Documents classified `not_about_humanoid_robots` by `ai_classify` are excluded from event extraction. | `silver.doc_relevance` → extraction step | To verify |
| BR-SCOPE-04 | Evaluation labels (`eval_labels_*.csv`) are kept outside the manifest and are never read by the pipeline. | Repository structure | Implemented |
| BR-SCOPE-05 | Only publicly accessible sources are used (no paywalled or login-only content). Full source text is stored only in the private Volume, never in Git. | Collection process; `.gitignore` | Implemented |

**Source types** (`dim_source.source_type`): `press_release`, `filing`, `news`, `policy`.
**Languages** (`dim_source.language`): `en`, `zh`.

---

## 3. Events (BR-EVT)

### 3.1 Event types

Fixed list. Definitions below are used verbatim in the extraction prompt and in table comments.

| `event_type` | Definition | Synonyms (EN / ZH) |
|---|---|---|
| `funding` | Financing, investment, IPO, M&A | raise, investment, round / 融资, 投资, 上市, 并购 |
| `partnership` | Collaboration, supply agreement, joint development, pilot deployment | deal, collaboration, pilot / 合作, 供货协议, 联合开发, 试点 |
| `product_launch` | New product, new version, or new component release | launch, unveil / 发布, 新品 |
| `production_plan` | Mass-production plans, capacity, factories, delivery targets | production, capacity, deliveries / 量产, 产能, 工厂, 交付 |
| `policy` | Government policy, standards, regulation | regulation, standard / 政策, 标准, 法规 |
| `other` | Cannot be assigned to any of the above. Used to monitor misclassification. | — |

### 3.2 Event rules

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-EVT-01 | `event_type` must be one of the six values in §3.1. Any other value returned by the model is set to `other`. | `silver.events_extracted` (06) | Implemented |
| BR-EVT-02 | `other` events are **excluded from analysis by default** and included only when explicitly requested. | `genie/instructions.md`; metric view filters (optional) | Implemented (instructions) |
| BR-EVT-03 | One document can contain multiple events. Extraction returns an array; one event = one row. Documents with zero events appear only in `silver.document_summaries` (`event_count = 0`). | `silver.events_extracted`, `silver.document_summaries` | Implemented |
| BR-EVT-04 | **Grain of `gold.fct_events`: one de-duplicated, real-world event.** Event attributes (type, date, amount, currency) are stored once, in the fact table only. | `gold.fct_events` | Implemented |
| BR-EVT-05 | `extracted_event_id` (e.g. `D0001_E01`) identifies one event record extracted from one document. `event_id` identifies one real-world event after de-duplication. All gold event tables obtain `event_id` via `silver.event_dedup_map`. | `silver.event_dedup_map`; gold SQL | Implemented (placeholder, see BR-EVT-06) |
| BR-EVT-06 | **De-duplication.** Two extracted events are the same real-world event when they have the same `event_type`, the same set of `company_id`s, and event dates within **14 days**. All source documents are retained in `bridge_event_source`; `source_count` = number of source documents. Events from the same document must not be merged without review. Approximate dates (BR-DATE-02) require extra care. | `silver.event_dedup_map` | **Planned** — currently `event_id = extracted_event_id`, `n_sources = 1` |
| BR-EVT-07 | Column naming: in `silver.events_extracted` and `silver.event_companies`, the current `event_id` column holds the **extracted** event ID and will be renamed `extracted_event_id`. | silver 06, 07 | Planned |

---

## 4. Dates and time periods (BR-DATE)

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-DATE-01 | The model returns `event_date` only if it is explicitly stated (or unambiguously inferable from relative wording such as "yesterday", using the publish date supplied in the prompt). Otherwise it returns null. | Extraction prompt (v1) | Implemented |
| BR-DATE-02 | **Date fallback.** `event_date = coalesce(try_to_date(<model date>), publish_date)`. The flag `date_is_publish_date = true` means the model found no event date and the **publish date was substituted**; the date is approximate (the event may have occurred earlier). It does **not** mean "event date equals publish date". | `silver.events_extracted` (06) | Implemented |
| BR-DATE-03 | When answering date-sensitive questions, results that rely on approximate dates (`date_is_publish_date = true`) should be flagged to the user. | `genie/instructions.md` | Implemented (instructions) |
| BR-DATE-04 | Calendar attributes (`year`, `quarter`, `year_quarter`, `month`) come from `gold.dim_date`, joined on `event_date`. | `gold.dim_date`; `mv_event_metrics` | Implemented |
| BR-DATE-05 | "Last year" / "去年" = the **previous calendar year** (e.g. asked in 2026 → 2025-01-01 to 2025-12-31). "Past 12 months" / "最近 12 个月" = rolling 12 months up to today. "This year" = current calendar year to date. | `genie/instructions.md` | Implemented (instructions) |
| BR-DATE-06 | Rename `date_is_publish_date` to a clearer name (`event_date_is_imputed`, or `event_date_source` with values `text` / `publish_date`). | silver 06 and downstream | Proposed |

---

## 5. Companies (BR-CO)

### 5.1 Company master data

`gold.dim_company` is built from `silver.company`, which is the `UNION ALL` of three curated seed files:

| Seed file | Content | `is_focus_company` |
|---|---|---|
| `company_maker.csv` | Selected humanoid robot makers | `true` |
| `company_tier1.csv` | Selected automotive tier-1 suppliers | `true` |
| `company_other.csv` | Companies discovered in events and confirmed manually (investors, customers, technology partners, other makers) | `false` |

**Focus companies (collection scope):** Tesla (Optimus), Figure AI, Agility Robotics, Apptronik, Unitree, UBTech, Schaeffler, Magna, Hyundai Mobis, Bosch or ZF (one selected). The seed files are authoritative; this list is informational.

**`company_type`** (what the company *is*) — fixed values:

| Value | Meaning |
|---|---|
| `humanoid_maker` | Develops or manufactures humanoid robots |
| `tier1` | Automotive tier-1 supplier |
| `investor` | Investment firm / corporate venture arm whose main role is investing |
| `customer` | Company whose main relation to the industry is buying or deploying robots |
| `technology_partner` | Provides chips, software, AI models or other technology |
| `other` | None of the above |

### 5.2 Company rules

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-CO-01 | `company_type` (what a company **is**) and `is_focus_company` (whether it is a **research target**) are independent attributes. Example: a tier-1 supplier not selected for the study is `company_type = 'tier1'`, `is_focus_company = false`. | `silver.company` | Implemented |
| BR-CO-02 | There is **one** company dimension. Companies are not split into separate dimension tables by type. Type-specific attributes, if needed, go into a sub-type extension table sharing `company_id` (e.g. `dim_company_tier1_detail`). | Gold model | Implemented |
| BR-CO-03 | `company_id` is a stable surrogate key with no business meaning and is never changed. `company_name` is the short name most commonly used in news (e.g. `UBTech`, `Humanoid`) and may be changed to improve matching. | `silver.company` | Implemented |
| BR-CO-04 | **Name matching:** an extracted company name matches a company when `upper(trim(extracted_name)) = upper(trim(company_name))`. The alias table (`silver.company_alias`) is kept but not used until real spelling variants appear (e.g. Chinese names, full legal names). | `silver.event_companies` (07) | Implemented |
| BR-CO-05 | Companies outside the focus list are **not errors**. After each new batch, unmatched names are reviewed via the candidate query: real company → add to `company_other.csv`; spelling variant of a known company → change `company_name` or enable the alias table; extraction error → do not add, log in `docs/prompt_issues.md`. | `07_company_candidates`; seed CSVs | Implemented (manual process) |
| BR-CO-06 | A company enters `dim_company` only after manual confirmation; names are never aggregated directly from extraction output into the dimension. | `silver.company` | Implemented |
| BR-CO-07 | Unmatched names stay in `silver.event_companies` with `is_matched = false` and are **excluded** from `gold.bridge_event_company` (`company_id IS NOT NULL`). Target: zero unmatched names, or only names confirmed as extraction errors. | silver 07; gold bridge | Implemented |
| BR-CO-08 | "Humanoid" refers to the UK humanoid robot company Humanoid (SKL Robotics), `company_id = humanoid_uk`. Because "humanoid" is also a common word, matches to this company must be checked against `evidence_quote` during evaluation. | Eval process | Implemented |
| BR-CO-09 | Prompt v2 will list the focus companies' standard names and instruct the model to use them; the original spelling is kept in `name_original`. | Extraction prompt v2 | Planned |

---

## 6. Event–company roles (BR-ROLE)

`role` describes what a company **did in a specific event**. It belongs to the relationship (`gold.bridge_event_company`), not to the company. The same company can have different roles in different events (e.g. Schaeffler as `investor`, `customer` and `partner`).

| `role` | Definition (proposed for prompt v2) |
|---|---|
| `target` | The company that receives the investment, is acquired, or is the subject of the transaction |
| `issuer` | The company issuing shares or making the announcement (e.g. IPO issuer, filing issuer) |
| `investor` | A company providing capital |
| `customer` | A company buying, ordering or deploying the product |
| `supplier` | A company supplying products, components or services |
| `partner` | A company in a collaboration without a clear buyer/seller relationship |

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-ROLE-01 | `role` is normalised with `lower(trim())`. | silver 07 | Implemented |
| BR-ROLE-02 | Within one event, the same company with the same role appears once; the same company with different roles is kept as separate rows. | silver 07 (`QUALIFY row_number()`) | Implemented |
| BR-ROLE-03 | **Known inconsistency:** in v1 extraction the recipient of funding is labelled sometimes `target` and sometimes `issuer`. Until prompt v2 fixes this, **`target` and `issuer` are treated as equivalent for funding**. | Metric definitions; `genie/instructions.md` | Implemented (workaround) |
| BR-ROLE-04 | Role definitions in this section are added to the extraction schema in prompt v2. | Extraction prompt v2 | Planned |

---

## 7. Amounts and currency (BR-AMT)

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-AMT-01 | `amount` is a number in the original currency; `currency` is an ISO-style code normalised with `upper()`. The model returns null when the amount is not stated; it never estimates. | Extraction prompt; silver 06 | Implemented |
| BR-AMT-02 | **Amounts in different currencies are never summed together.** Aggregations use `amount_usd`, or group by `currency`. | Metric view; `genie/instructions.md` | Planned (`amount_usd`) / Implemented (instructions) |
| BR-AMT-03 | `amount_usd = amount × fixed annual average exchange rate` for the year of `event_date`. The rate table and its source are documented in the column comment. | `gold.fct_events` | Planned — rates TBD |
| BR-AMT-04 | **Funding amount** = `SUM(amount_usd)` over events with `event_type = 'funding'` only. Amounts on other event types (e.g. contract values in partnerships) are not funding. | Metric view `mv_event_metrics` | Planned (current `total_amount` sums all types — to be replaced) |
| BR-AMT-05 | **Funding amount by company** is attributed only to companies with `role IN ('target','issuer')` (the recipient). Investors are not credited with the amount they invested. | Metric definition; `genie/instructions.md` | Implemented (instructions) |
| BR-AMT-06 | Amounts are never summed after joining `fct_events` to a bridge table (one event → many rows would multiply the amount). Amount metrics are defined only on the event grain (`mv_event_metrics`). | Metric view design; `genie/instructions.md` | Implemented |
| BR-AMT-07 | "Total funding raised by a company across rounds" counts each funding event once per recipient company. | Metric definition | Implemented (via BR-AMT-05/06) |

---

## 8. Counting (BR-CNT)

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-CNT-01 | Number of events = `COUNT(DISTINCT event_id)`. Row counts are never used as event counts after any bridge join. | `mv_event_company_metrics.distinct_event_count`; instructions | Implemented |
| BR-CNT-02 | Number of companies = `COUNT(DISTINCT company_id)`. | Metric view (`distinct_company_count`) | Planned |
| BR-CNT-03 | `event_company_count` counts event × company × role combinations; it is **not** an event count. | `mv_event_company_metrics` comment | Implemented |
| BR-CNT-04 | `source_count` = number of documents reporting the event. Until de-duplication (BR-EVT-06) it is always 1. | `gold.fct_events` | Implemented (placeholder) |
| BR-CNT-05 | Ratios (e.g. "share of partnerships involving a tier-1") are computed as numerator and denominator separately, then divided — never as an average of row-level ratios. | Metric view | Planned |

---

## 9. Technology classification (BR-TECH)

Value chain classification used in `gold.dim_technology` (seed, 6 fixed values):

| `technology_area` | Definition (draft) | Examples |
|---|---|---|
| `sensors` | Components that perceive the environment or the robot's own state | camera, radar, LiDAR, IMU, force/torque sensor, position sensor |
| `compute_electronics` | Processing hardware and control electronics | AI chips, SoCs, controllers, ECUs, motor drivers |
| `software_ai` | Software and AI models | perception, motion planning, control software, foundation models |
| `actuators` | Components producing motion | motors, harmonic reducers, planetary roller screws, dexterous hands |
| `battery_power` | Energy storage and power systems | battery packs, BMS, charging, power distribution |
| `not_specified` | The event does not mention a specific technology area | — |

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-TECH-01 | An event can have several technology areas (`bridge_event_technology`). | gold bridge | Implemented |
| BR-TECH-02 | `not_specified` must not appear together with another technology area on the same event. | Quality check 7 | Implemented (check) |
| BR-TECH-03 | `not_specified` is kept as a dimension member so coverage can be measured; it is excluded when answering "which technology areas…" questions unless asked. | `dim_technology`; instructions | Implemented |
| BR-TECH-04 | `components` (free-text component names) are **not** part of the gold model until prompt v2 restricts them to concrete parts (no product names, robot names or technology categories). Product names move to a new `product_name` field. | Gold model; prompt v2 | Planned |
| BR-TECH-05 | Definitions of non-sensor technology areas above are drafts and must be confirmed before prompt v2. | This document | Proposed |

---

## 10. AI extraction governance (BR-AI)

| ID | Rule | Enforced in | Status |
|---|---|---|---|
| BR-AI-01 | The model extracts only information **explicitly stated** in the text; when uncertain it returns null. | Extraction prompt | Implemented |
| BR-AI-02 | Output must conform to a JSON schema (`responseFormat` with `strict: true`). Schema changes are applied in three places: the `responseFormat` (incl. `required`), the parsing view `STRUCT<…>`, and `events_extracted`. | silver 05, 06 | Implemented |
| BR-AI-03 | Every event includes an `evidence_quote` that must appear verbatim in the cleaned source text. | Quality check 4 | Implemented (check) |
| BR-AI-04 | `silver.documents_extractions` is **append-only** and is never replaced. Each row records `prompt_version`, `model_name`, `extracted_at`, `ai_raw_json`, `ai_error`. | silver 05 | Implemented |
| BR-AI-05 | Incremental processing: a document is skipped if a successful extraction (`ai_error IS NULL`) already exists for the same `doc_id` and `prompt_version`. Failed extractions are retried automatically. | silver 05 (`NOT EXISTS`) | Implemented |
| BR-AI-06 | Downstream tables use only the **active prompt version** (currently `v1`), taking the latest successful result per `doc_id`. Switching versions changes three places: the version written, the incremental condition, the view filter. | `silver.v_extractions_parsed` | Implemented |
| BR-AI-07 | A new prompt version is adopted only after it improves the targeted fields on the 30-document eval set **without regression** on other fields. Results are recorded in `sql/extract/CHANGELOG.md` and `docs/evaluation.md`. | Eval process | Planned |
| BR-AI-08 | Summaries are always in English (`summary_en`); company names are output as English standard names, with the original spelling in `name_original`. | Extraction prompt | Implemented |
| BR-AI-09 | Rules that can be expressed deterministically (date fallback, value normalisation, enumerations) are implemented in SQL, not delegated to the model. AI output is parsed with `try_` functions so a single bad value cannot fail the table. | silver 06 | Implemented |
| BR-AI-10 | AI functions are run on small samples before full runs, to stay within Free Edition fair-usage limits. | Process | Implemented |

---

## 11. Data quality controls (BR-DQ)

Checks run after every batch (`09_silver_quality_checks`). Each check has an expected result; a deviation must be explained before gold is rebuilt.

| ID | Check | Expected |
|---|---|---|
| BR-DQ-01 | AI calls with `ai_error IS NOT NULL` | 0 (or retried) |
| BR-DQ-02 | Successful calls whose JSON fails to parse | 0 |
| BR-DQ-03 | Rows in `events_extracted` = `SUM(event_count)` in `document_summaries` | Equal |
| BR-DQ-04 | `evidence_quote` not found in source text | 0, or reviewed |
| BR-DQ-05 | `event_type` distribution | No unexpected values; `other` share monitored |
| BR-DQ-06 | `amount` without `currency`, or `funding` events without `amount` | Reviewed (missing amounts are allowed if not disclosed) |
| BR-DQ-07 | `not_specified` combined with another technology area | 0 |
| BR-DQ-08 | Unmatched company names in `event_companies` | 0, or confirmed extraction errors |
| BR-DQ-09 | Bridge foreign keys exist in their dimensions (referential integrity) | 100% (dbt `relationships` tests in Phase 5) |
| BR-DQ-10 | Join fan-out in `event_companies`: `count(*) = count(DISTINCT event_id, company_pos)` | Equal |
| BR-DQ-11 | Coverage after collection: ≥ 8 documents per focus company; ≥ 25% Chinese; ≥ 10 candidates per event type; publish dates within the last 1–2 years | Met, or gaps documented |

---

## 12. Known limitations

These must be stated in the README and in Genie instructions.

1. **Sample, not census.** Results reflect the collected documents only (BR-SCOPE-01). With the 6-document pilot, statistics demonstrate the pipeline but have no business meaning.
2. **No event de-duplication yet** (BR-EVT-06). An event reported by several documents is counted several times.
3. **Approximate dates** where `date_is_publish_date = true` (BR-DATE-02).
4. **Role inconsistency** between `target` and `issuer` in v1 (BR-ROLE-03).
5. **No currency conversion yet** (BR-AMT-03); amounts must be grouped by currency until `amount_usd` exists.
6. **Technology areas** are often `not_specified`; possible under-classification is under review.
7. **"Humanoid" ambiguity** in company matching (BR-CO-08).

---

## 13. Open questions

| # | Question | Owner | Target |
|---|---|---|---|
| Q1 | Confirm whether extraction is filtered by `doc_relevance` (BR-SCOPE-03) | Owner | Before 100-doc run |
| Q2 | Choose exchange-rate source and years for `amount_usd` | Owner | Before gold v2 |
| Q3 | Finalise `company_type` values in the data dictionary | Owner | Before 100-doc run |
| Q4 | Confirm technology-area definitions (BR-TECH-05) | Owner | Before prompt v2 |
| Q5 | Bosch or ZF as the fourth tier-1 focus company | Owner | During collection |
| Q6 | Whether Chinese company names require the alias table | Owner | After first Chinese batch |

---

## 14. Change log

| Version | Date | Change | Author |
|---|---|---|---|
| 0.1 | 2026-10-24 | Initial draft consolidating decisions from the implementation plan and silver/gold design notes | Project owner |
