-- =====================================================================
-- gold layer: Unity Catalog Metric Views (spec version 1.1)
--
-- Purpose: give Genie / Text-to-SQL (and any other AI consumer) a
-- pre-aggregated, semantically unambiguous set of measures over
-- fct_events, instead of making the model guess a GROUP BY / join
-- every time someone asks a business question.
--
-- Requires a Databricks Runtime new enough for YAML spec 1.1
-- (display_name / synonyms on fields and measures). Serverless /
-- Free Edition compute is generally new enough; on a classic cluster,
-- confirm the runtime supports spec 1.1 before deploying.
-- Reference: https://docs.databricks.com/aws/en/metric-views/yaml-ref
--
-- Run AFTER comments.sql (not required, but keeps metadata complete
-- from the start) and after all 8 gold tables exist.
-- =====================================================================

-- ---------------------------------------------------------------------
-- gold.mv_event_metrics
-- Grain: fct_events (one row per de-duplicated event), joined 1:1 to
-- dim_date on event_date. Safe to aggregate directly -- no fan-out,
-- so SUM/AVG/COUNT cannot double-count.
-- ---------------------------------------------------------------------
CREATE VIEW humanoid_robotics.gold.mv_event_metrics
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1

comment: >
  Metric view over fct_events joined to dim_date: event counts and
  funding amounts, sliceable by event_type, region, currency, and
  year/quarter. Primary semantic layer for Genie Text-to-SQL questions
  about event volume and funding amounts.

source: humanoid_robotics.gold.fct_events

joins:
  - name: dim_date
    source: humanoid_robotics.gold.dim_date
    on: source.event_date = dim_date.date

dimensions:
  - name: event_type
    expr: event_type
    comment: 'Event category: funding, partnership, product_launch, production_plan, policy, other.'
  - name: region
    expr: region
    comment: 'Region where the event took place.'
  - name: currency
    expr: currency
    comment: 'ISO 4217 currency code of amount/funding_amount. Always group by this before summing a monetary measure -- amounts are in native currency, not converted to a common currency.'
  - name: year
    expr: dim_date.year
  - name: quarter
    expr: dim_date.quarter
  - name: year_quarter
    expr: dim_date.year_quarter

measures:
  - name: event_count
    expr: COUNT(event_id)
    comment: 'Number of de-duplicated events.'
    display_name: 'Event Count'
    synonyms: ['number of events', 'event volume']
  - name: funding_event_count
    expr: COUNT(CASE WHEN event_type = 'funding' THEN event_id END)
    comment: 'Number of events where event_type = funding.'
    display_name: 'Funding Event Count'
  - name: partnership_count
    expr: COUNT(CASE WHEN event_type = 'partnership' THEN event_id END)
    comment: 'Number of events where event_type = partnership.'
    display_name: 'Partnership Count'
  - name: funding_amount
    expr: SUM(CASE WHEN event_type = 'funding' THEN amount END)
    comment: >
      Total funding amount in NATIVE currency (no FX conversion exists
      in this schema -- there is no rate table). Only meaningful
      grouped by the currency dimension; summing across currencies
      mixes units and is wrong. Do not rename/treat as USD without
      adding a real FX conversion table first.
    display_name: 'Funding Amount (native currency)'
    synonyms: ['funding total', 'total raised']
  - name: avg_amount
    expr: AVG(amount)
    comment: 'Average event amount in native currency. Group by currency -- see funding_amount comment.'
$$;

-- ---------------------------------------------------------------------
-- gold.mv_event_company_metrics
-- Grain: one row per (event, company, role) via bridge_event_company.
-- This join fans fct_events OUT (one event -> many companies), so
-- event_company_count means "event-company-role combinations", not
-- distinct events -- use distinct_event_count for a true event count
-- sliced by company/role. Monetary amounts are intentionally NOT
-- aggregated in this view (joining to bridge_event_company would
-- double-count an event's amount once per linked company) -- use
-- mv_event_metrics for funding_amount.
-- ---------------------------------------------------------------------
CREATE VIEW humanoid_robotics.gold.mv_event_company_metrics
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1

comment: >
  Metric view over bridge_event_company joined to fct_events and
  dim_company: event counts sliced by company and role (e.g. "how many
  funding events was Company X an investor in"). Use distinct_event_count,
  not event_company_count, when a company/role combination should not
  be double-counted. Does not aggregate monetary amounts -- see
  mv_event_metrics.funding_amount for that.

source: humanoid_robotics.gold.bridge_event_company

joins:
  - name: fct_events
    source: humanoid_robotics.gold.fct_events
    on: source.event_id = fct_events.event_id
  - name: dim_company
    source: humanoid_robotics.gold.dim_company
    on: source.company_id = dim_company.company_id

dimensions:
  - name: role
    expr: role
    comment: 'Company role in this event: investor, target, partner, customer, supplier, issuer.'
  - name: event_type
    expr: fct_events.event_type
  - name: company_name
    expr: dim_company.company_name
  - name: company_type
    expr: dim_company.company_type

measures:
  - name: event_company_count
    expr: COUNT(*)
    comment: 'Row count at the (event, company, role) grain -- NOT a distinct event count. See distinct_event_count.'
  - name: distinct_event_count
    expr: COUNT(DISTINCT source.event_id)
    comment: 'Number of distinct events, correctly counted once even when an event has multiple linked companies/roles.'
    display_name: 'Distinct Event Count'
  - name: distinct_company_count
    expr: COUNT(DISTINCT dim_company.company_id)
    comment: 'Number of distinct companies in the current slice.'
    display_name: 'Distinct Company Count'
  - name: target_or_issuer_event_count
    expr: COUNT(DISTINCT CASE WHEN role IN ('target', 'issuer') THEN source.event_id END)
    comment: 'Distinct events where this company was the target or issuer (the receiving side of funding/investment), as opposed to investor/partner/customer/supplier.'
    display_name: 'Target/Issuer Event Count'
$$;
