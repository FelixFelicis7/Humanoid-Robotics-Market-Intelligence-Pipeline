-- =====================================================================
-- gold.fct_events
-- Converted from: scripts/gold/01_gold_fct_events.ipynb (original kept in sync)
-- Reads: silver.event_dedup_map, silver.events_extracted
-- Job task: gold_fct_events (SQL file)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.fct_events AS
WITH rep AS (
  SELECT m.event_id,
         m.extracted_event_id,
         m.doc_id    AS primary_source_doc_id,
         m.n_sources AS source_count
  FROM humanoid_robotics.silver.event_dedup_map m
  WHERE m.extracted_event_id = m.event_id
)
SELECT
  r.event_id,
  e.event_type,
  e.event_date,
  e.date_is_publish_date,
  e.amount,
  e.currency,
  e.region,
  e.evidence_quote,
  r.primary_source_doc_id,
  r.source_count
FROM rep r
JOIN humanoid_robotics.silver.events_extracted e
  ON e.event_id = r.extracted_event_id;
