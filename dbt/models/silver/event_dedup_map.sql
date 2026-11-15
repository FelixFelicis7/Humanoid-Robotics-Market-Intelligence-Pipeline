-- silver.event_dedup_map: extracted event -> de-duplicated event.
-- Migrated from scripts/silver/sql/11_silver_event_dedup.sql (logic unchanged).
-- Placeholder v0: 1 extracted event = 1 event (BR-EVT-06 planned).

SELECT e.event_id AS extracted_event_id,
       e.doc_id,
       e.event_type,
       e.event_date,
       e.date_is_publish_date,
       e.event_id AS event_id,
       1          AS n_sources
FROM {{ ref('events_extracted') }} e
