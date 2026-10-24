# Genie space instructions — Humanoid Robotics Market Intelligence

Paste only the **General instructions** section below into the Genie space's instructions field. It's kept short on purpose: Databricks' own guidance treats text instructions as "a last resort" and recommends "a small, well-organized set" because a long block becomes harder for Genie to prioritize over a long conversation (see [Curate an effective Genie Agent](https://docs.databricks.com/aws/en/genie-agents/best-practices)). Anything already captured in the deployed table/column comments or the metric views' own `comment`/`synonyms` fields (`gold.mv_event_metrics`, `gold.mv_event_company_metrics` — see `scripts/gold/sql/comments.sql` and `metric_views.sql`) is **not** repeated here; Genie reads that metadata directly.

Full rationale and `BR-*` rule IDs live in [`docs/business_rules.md`](../docs/business_rules.md) — don't paste that file into Genie. It documents several `Planned` items (e.g. `amount_usd`) that don't exist yet as columns, and pasting it as instructions would send Genie looking for them.

`docs/prompt_issues.md` is a human-facing issue log, not something Genie reads — no need to reference it from inside the instructions themselves.

---

## General instructions

- This data covers only the documents collected into the manifest, not the whole humanoid robotics market — phrase answers as "of the documents in this dataset," not "in the industry."
- Prefer `gold.mv_event_metrics` and `gold.mv_event_company_metrics` over ad hoc queries on `fct_events` and the bridge tables.
- Exclude `event_type = 'other'` unless the user asks for uncategorized events. Exclude `technology_area = 'not_specified'` unless the question is specifically about coverage gaps.
- `event_type` synonyms: `funding` = raise/investment/round/融资/投资/上市/并购 · `partnership` = deal/collaboration/pilot/合作/供货协议/联合开发/试点 · `product_launch` = launch/unveil/发布/新品 · `production_plan` = production/capacity/deliveries/量产/产能/工厂/交付 · `policy` = regulation/standard/政策/标准/法规.
- "Last year"/"去年" = the previous calendar year. "Past 12 months"/"最近 12 个月" = a rolling 12-month window ending today. "This year" = the current calendar year to date.
- The recipient of a funding round is labeled `target` in some records and `issuer` in others — treat the two as equivalent when answering funding-recipient questions.
- If an answer depends on an exact event date, check whether it was inferred from the document's publish date (flagged on `fct_events`) and say so when it was.
- Event de-duplication isn't implemented yet — a count like "how many times was this reported" isn't reliable; say so if asked.
- "Humanoid" as a company name means the UK company (SKL Robotics) — confirm via `evidence_quote` before treating a match as that specific company, since "humanoid" is also an ordinary word.
