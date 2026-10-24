# Extraction evaluation

This document defines how the accuracy of the AI extraction step (`ai_query` in `scripts/silver/05_silver_document_extraction.dbquery.ipynb`, prompt `v1`) is measured against manually-defined ground truth. It is the evaluation process referenced by [`docs/business_rules.md`](business_rules.md) rule **BR-AI-07**: a new prompt version is adopted only after it improves the targeted fields on the eval set **without regressing** other fields.

**Status: methodology defined, results not yet run.** The pilot manifest (below) already carries hand-written expected outputs for 6 documents, but the actual `ai_query` output for those documents lives in the Databricks workspace (`humanoid_robotics.silver.documents_extractions`) and has not been pulled into this repo for scoring. The *Results* section at the bottom is a placeholder to fill in once that comparison is run — no accuracy numbers are reported here until they are real.

## Ground truth: the pilot set

`data/manifest/manifest_pilot.csv` (collection-side file, not synced to this repo — see `docs/business_rules.md` BR-SCOPE-04 on where evaluation labels live) carries two columns that make up the current ground truth:

- `in_eval_set` (`Y`/`N`) — flags which documents are held out for evaluation rather than used only to build the gold tables.
- `expected_events` — a short, human-written description of the event(s) a correct extraction should produce for that document.
- `test_purpose` — what specific extraction behavior that document is meant to stress-test (parsing edge cases, not general coverage).

All 6 pilot documents (`D0001`–`D0006`) are flagged `in_eval_set = Y`. Each one targets a specific, deliberately chosen failure mode:

| doc_id | Expected event(s) | What it tests |
|---|---|---|
| D0001 | `funding` (Schaeffler minority investment, amount undisclosed → null) + `partnership` (Schaeffler to buy Digit units for its plants) | Multi-event extraction from one article; a null amount must stay null, not be guessed; the same company (Schaeffler) holds two different roles across the two events. |
| D0002 | `funding`, >$1B USD, Series C, lead investor Parkway, ~10 other investors | Large-number parsing (">$1B"); many investors linking to one event via the company bridge; the funding-amount double-counting risk when a view joins through that bridge (see `genie/instructions.md`, BR-AMT-06). |
| D0003 | `partnership` (actuator supply for Atlas) and possibly `production_plan` (Hyundai Motor Group's "tens of thousands of robots" plan) | Whether background/context sentences (an unrelated $26B HMG investment figure mentioned in the article) get misclassified as events of their own. |
| D0004 | `partnership` (binding deployment agreement, robots-as-a-service) + `partnership`/supply (5-year actuator supply, >50% share) + `production_plan` (four-digit unit volume by 2032) | Vague/approximate quantities ("four-digit", "seven-digit" units) — does the model record them faithfully or fabricate a precise number; "Humanoid" (the UK company) is not yet in the seed company list, so this also tests the unmatched-name path (BR-CO-05, `docs/prompt_issues.md` PI-001). |
| D0005 | `partnership`/order, CNY 250,000,000, Walker S2, customer undisclosed | Chinese-language extraction; non-USD currency; English `summary_en` generation from Chinese source text; company-name standardization (优必选 → UBTech); an explicitly undisclosed customer should stay null, not be guessed. |
| D0006 | `production_plan` (mass production & delivery start); background mentions of a CNY 159M Zigong order and the CNY 250M September order — the latter is **the same real-world event as D0005** | Cross-document, cross-language event de-duplication (BR-EVT-06) — this is the one pilot case that directly exercises the de-dup placeholder's current limitation (see Known Limitations below). |

## What gets measured

Once the actual `documents_extractions` output for these 6 documents is available, score it against the table above on:

1. **Event-count accuracy** — does the extracted event count per document match the expected count (accounting for D0005/D0006 being one real event, not two, once de-dup is implemented)?
2. **Field-level precision/recall**, per extracted field, averaged across all extracted events in the eval set:
   - `event_type` (exact match against expected classification)
   - `event_date` (present only when explicitly stated; correctly null + `date_is_publish_date = true` otherwise — BR-DATE-02)
   - `amount` / `currency` (correct value when disclosed; correctly null when the source says "undisclosed")
   - `companies[].role` (correct role per company, allowing `target`/`issuer` as equivalent for funding per the current known workaround — BR-ROLE-03)
   - `technology_areas` (correct set, including correctly leaving it `not_specified` when the source doesn't name a technology)
   - `evidence_quote` (present in the source text verbatim — this is a pass/fail structural check, not a graded field; see BR-AI-03 and `scripts/gold/09_gold_bridge_table_quality_checks.ipynb` quality check 4)
3. **Company-name matching rate** — share of extracted company names that resolve to `dim_company` via the matching rule in BR-CO-04, vs. falling through to `docs/prompt_issues.md` as an unmatched/extraction-error case.
4. **De-duplication accuracy** (once BR-EVT-06 is implemented) — specifically whether D0005 and D0006 collapse into one `event_id` with `source_count = 2`.

## Scaling beyond the pilot

The pilot set (6 documents) is enough to exercise each known edge case once, not to produce a statistically meaningful accuracy number. Per `docs/business_rules.md` BR-AI-07, prompt-version decisions are made against a **30-document eval set** before being adopted — the 6-document pilot set above is a subset of that larger set, chosen to cover the failure modes above plus straightforward cases.

## Results

_Not yet run. Fill in after pulling `silver.documents_extractions` / `silver.events_extracted` output for the eval-set `doc_id`s and scoring against the table above._

| Prompt version | Eval set size | Event-count accuracy | Field-level precision/recall | Company match rate | Notes |
|---|---|---|---|---|---|
| `v1` | — | — | — | — | Pending |

## Known limitations affecting evaluation

- Event de-duplication (BR-EVT-06) is a placeholder today — D0005/D0006 will currently score as two events instead of one until it's implemented, which is expected and not itself an extraction error.
- `target`/`issuer` role inconsistency (BR-ROLE-03) is treated as a pass for funding events under the current workaround, not scored as an error, until prompt `v2` (see `sql/extract/CHANGELOG.md`) resolves it at the source.
