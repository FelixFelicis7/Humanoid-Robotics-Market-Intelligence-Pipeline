-- gold.bridge_event_source: event x source document.
-- Migrated from scripts/gold/sql/08_gold_bridge_event_source.sql (logic unchanged).
-- depends_on: {{ ref('fct_events') }}
-- depends_on: {{ ref('dim_source') }}

SELECT
  event_id,
  doc_id,
  max(extracted_event_id = event_id) AS is_primary_source
FROM {{ source('silver_legacy', 'event_dedup_map') }}
GROUP BY event_id, doc_id
