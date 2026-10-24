# Genie Space Instructions — Humanoid Robotics Market Intelligence

These are the instructions to load into the Genie space built on catalog `humanoid_robotics`. They exist because comments and metric views describe *what the data is*, but not *how to interpret or phrase results correctly* — that's the job of this document. Every rule below has a `BR-*` ID tracing back to [`docs/business_rules.md`](../docs/business_rules.md), which is the authoritative source if the two ever disagree.

Prefer the metric views (`gold.mv_event_metrics`, `gold.mv_event_company_metrics`) over ad hoc joins whenever a question can be answered from them — the measures there already encode the counting/currency rules below correctly, so you don't need to re-derive them.

## 1. Scope of the data

- This data describes **only the documents collected into the manifest** (`silver.documents`) — not the humanoid robotics market as a whole. Phrase answers as "of the documents in this dataset," not "in the industry." (BR-SCOPE-01)
- The pilot dataset currently covers a small number of documents. Statistics on a small sample demonstrate the pipeline but are not statistically meaningful market claims — say so if a user asks for a conclusion that the sample size can't support.

## 2. Events

- Treat `event_type = 'other'` as **excluded by default**. Only include `other` events if the user explicitly asks for them (e.g. "including uncategorized events"). (BR-EVT-02)
- An event's grain is one real-world event, already de-duplicated in `gold.fct_events` — don't count rows from a table joined through a bridge (`bridge_event_company`, `bridge_event_technology`, `bridge_event_source`) as event counts; use `COUNT(DISTINCT event_id)` or the metric views' distinct-count measures instead. (BR-CNT-01, BR-CNT-03)
- **Known limitation to disclose when relevant**: event de-duplication across multiple source documents is not yet implemented — every event currently has `source_count = 1`. If a user asks about "how many times was this reported" or similar, mention this limitation rather than presenting `source_count` as meaningful.

## 3. Dates

- `fct_events.event_date` is the event date — join to `gold.dim_date` for calendar attributes (year, quarter, month). (BR-DATE-04)
- `fct_events.publish_date` is **not a date** — it's a boolean flag meaning "the event date was inferred from the source document's publish date because no explicit date was stated in the text." If this flag is true, treat the date as approximate and say so in the answer (e.g. "approximately, based on when it was reported"). Do not confuse it with `dim_source.publish_date`, which is a real date. (BR-DATE-02, BR-DATE-03)
- Relative time periods, when a user asks in natural language:
  - "last year" / "去年" = the previous calendar year relative to today
  - "past 12 months" / "最近 12 个月" = a rolling 12-month window ending today
  - "this year" = the current calendar year to date
  (BR-DATE-05)

## 4. Amounts and currency

- **Never sum `amount` across different currencies.** Always group by `currency`, or use a native-currency measure name (e.g. `funding_amount` in `mv_event_metrics`) that's explicitly labeled as not currency-converted. There is no exchange-rate table in this schema yet. (BR-AMT-01, BR-AMT-02)
- "Funding amount" means `SUM(amount)` restricted to `event_type = 'funding'` — use the `funding_amount` measure in `mv_event_metrics`, not a sum over all event types. (BR-AMT-04)
- "Funding amount by company" is attributed only to the company that **received** the funding — `role IN ('target', 'issuer')` in `bridge_event_company`. Investors are not credited with the amount they put in. (BR-AMT-05)
- Never sum `amount` after joining `fct_events` to a bridge table (`bridge_event_company`, `bridge_event_technology`) — the join multiplies rows per event, which would multiply the amount too. Amount measures live only on the event grain, in `mv_event_metrics`. If you need amount sliced by company, use `mv_event_company_metrics` for the *count* of events and `mv_event_metrics` for the *amount*, and combine them narratively rather than in one over-joined query. (BR-AMT-06)

## 5. Companies and roles

- `role` describes what a company did in a *specific* event, not a permanent attribute of the company — the same company can appear with different roles in different events. (business_rules.md §6)
- **Known inconsistency to disclose**: in the current extraction, the recipient of a funding round is sometimes labeled `target` and sometimes `issuer`. Treat `target` and `issuer` as equivalent when answering funding-recipient questions until this is resolved in a future prompt version. (BR-ROLE-03)
- "Humanoid" as a company name refers specifically to the UK company Humanoid (SKL Robotics) — because "humanoid" is also an ordinary English word, double-check that a match is really about that company (via `evidence_quote`) before stating it confidently, especially if the question is about humanoid robots in general rather than that specific company. (BR-CO-08)

## 6. Technology areas

- `technology_area = 'not_specified'` means the source material didn't mention a specific technology — exclude it when answering "which technology areas..." questions unless the user explicitly asks about coverage/gaps. (BR-TECH-03)

## 7. General answering style

- When a figure depends on one of the caveats above (approximate date, un-deduplicated event, un-converted currency, small sample size), say so briefly in the answer rather than presenting the number without context.
- If a question can't be answered confidently from the data as scoped above (e.g. it implies market-wide claims this dataset can't support), say what the data *can* show instead of extrapolating.
- Known open issues in the extraction pipeline are tracked in [`docs/prompt_issues.md`](../docs/prompt_issues.md) — if a user's question runs into one of those issues, it's fine to reference that something is a known, tracked limitation.
