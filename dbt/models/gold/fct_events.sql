-- gold.fct_events: one row per de-duplicated event.
-- Migrated from scripts/gold/sql/01_gold_fct_events.sql (logic unchanged).
-- Parents of the foreign keys added in schema.yml (built first):
-- depends_on: {{ ref('dim_date') }}
-- depends_on: {{ ref('dim_source') }}

WITH rep AS (
  SELECT m.event_id,
         m.extracted_event_id,
         m.doc_id    AS primary_source_doc_id,
         m.n_sources AS source_count
  FROM {{ source('silver_legacy', 'event_dedup_map') }} m
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
JOIN {{ source('silver_legacy', 'events_extracted') }} e
  ON e.event_id = r.extracted_event_id
