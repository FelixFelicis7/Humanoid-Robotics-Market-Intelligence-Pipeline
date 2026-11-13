-- gold.bridge_event_technology: event x technology area.
-- Migrated from scripts/gold/sql/07_gold_bridge_event_technology.sql (logic unchanged).
-- depends_on: {{ ref('fct_events') }}
-- depends_on: {{ ref('dim_technology') }}

SELECT DISTINCT
  m.event_id,
  x.technology_id
FROM (
  SELECT event_id AS extracted_event_id,
         explode(technology_areas) AS technology_id
  FROM {{ source('silver_legacy', 'events_extracted') }}
) x
JOIN {{ source('silver_legacy', 'event_dedup_map') }} m
  ON m.extracted_event_id = x.extracted_event_id
