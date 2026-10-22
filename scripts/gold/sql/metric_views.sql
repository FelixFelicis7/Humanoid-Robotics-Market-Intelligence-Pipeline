-- =====================================================================
-- gold layer: Unity Catalog Metric Views
--
-- Purpose: give Genie / Text-to-SQL (and any other AI consumer) a
-- pre-aggregated, semantically unambiguous set of measures over
-- fct_events, instead of making the model guess a GROUP BY / join
-- every time someone asks a business question.
--
-- Run AFTER comments.sql (not required, but keeps metadata complete
-- from the start) and after all 8 gold tables exist.
--
-- NOTE: Unity Catalog Metric Views are a newer Databricks feature and
-- the YAML spec below follows the documented syntax as of this
-- writing. Validate against your workspace's current Databricks
-- runtime / docs before relying on it -- the syntax has been known to
-- evolve while the feature is in preview.
-- =====================================================================

-- ---------------------------------------------------------------------
-- gold.mv_event_metrics
-- Grain: fct_events (one row per de-duplicated event), joined 1:1 to
-- dim_date on event_date. Safe to aggregate directly -- no fan-out,
-- so SUM/AVG(amount) cannot double-count.
-- ---------------------------------------------------------------------
CREATE VIEW humanoid_robotics.gold.mv_event_metrics
WITH METRICS
LANGUAGE YAML
AS $$
version: 0.1

source: humanoid_robotics.gold.fct_events

joins:
  - name: dim_date
    source: humanoid_robotics.gold.dim_date
    on: source.event_date = dim_date.date

dimensions:
  - name: event_type
    expr: event_type
  - name: region
    expr: region
  - name: currency
    expr: currency
  - name: year
    expr: dim_date.year
  - name: quarter
    expr: dim_date.quarter
  - name: year_quarter
    expr: dim_date.year_quarter

measures:
  - name: event_count
    expr: COUNT(event_id)
  - name: funding_event_count
    expr: COUNT(CASE WHEN event_type = 'funding' THEN event_id END)
  - name: total_amount
    expr: SUM(amount)
  - name: avg_amount
    expr: AVG(amount)
$$;

COMMENT ON TABLE humanoid_robotics.gold.mv_event_metrics IS
  'Metric view over fct_events joined to dim_date: event counts and funding amount totals/averages, sliceable by event_type, region, currency, year/quarter. Primary semantic layer for Genie Text-to-SQL questions about event volume and funding amounts.';

-- ---------------------------------------------------------------------
-- gold.mv_event_company_metrics
-- Grain: one row per (event, company, role) via bridge_event_company.
-- This join fans fct_events OUT (one event -> many companies), so
-- event_count here means "event-company-role combinations", not
-- distinct events -- use COUNT(DISTINCT event_id) for a true event
-- count sliced by company/role. amount is intentionally NOT summed
-- directly off this view (it would double-count an event's amount
-- once per company) -- if you need "funding amount by investor",
-- confirm the dimension cardinality in your workspace first, or
-- pre-aggregate in a plain SQL view instead of a metric view.
-- ---------------------------------------------------------------------
CREATE VIEW humanoid_robotics.gold.mv_event_company_metrics
WITH METRICS
LANGUAGE YAML
AS $$
version: 0.1

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
    expr: source.role
  - name: event_type
    expr: fct_events.event_type
  - name: company_name
    expr: dim_company.company_name
  - name: company_type
    expr: dim_company.company_type

measures:
  - name: event_company_count
    expr: COUNT(*)
  - name: distinct_event_count
    expr: COUNT(DISTINCT source.event_id)
$$;

COMMENT ON TABLE humanoid_robotics.gold.mv_event_company_metrics IS
  'Metric view over bridge_event_company joined to fct_events and dim_company: event counts sliced by company and role (e.g. "how many funding events was Company X an investor in"). Use distinct_event_count, not event_company_count, when a company/role combination should not be double-counted. Does not aggregate amount -- see mv_event_metrics for that, or pre-aggregate in a plain SQL view to avoid double-counting per company.';
