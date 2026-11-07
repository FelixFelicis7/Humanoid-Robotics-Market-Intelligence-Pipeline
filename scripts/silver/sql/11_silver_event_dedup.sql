-- =====================================================================
-- silver.event_dedup_map (placeholder: 1 extracted event = 1 event)
-- Converted from: scripts/silver/11_silver_event_dedup.dbquery.ipynb (original kept unchanged)
-- Reads: silver.events_extracted
-- Job task: silver_11_event_dedup (SQL file)
-- =====================================================================

-- 11_silver_event_dedup（v0）

CREATE OR REPLACE TABLE humanoid_robotics.silver.event_dedup_map AS
SELECT e.event_id AS extracted_event_id,
       e.doc_id,
       e.event_type,
       e.event_date,
       e.date_is_publish_date,
       e.event_id AS event_id,      
       1          AS n_sources
FROM humanoid_robotics.silver.events_extracted e;
