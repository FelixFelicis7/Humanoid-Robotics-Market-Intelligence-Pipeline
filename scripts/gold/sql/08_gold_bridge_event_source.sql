-- =====================================================================
-- gold.bridge_event_source
-- Converted from: scripts/gold/08_gold_bridge_event_source.ipynb (original kept in sync)
-- Reads: silver.event_dedup_map
-- Job task: gold_bridge_event_source (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.bridge_event_source AS
SELECT
  event_id,
  doc_id,
  max(extracted_event_id = event_id) AS is_primary_source
FROM humanoid_robotics.silver.event_dedup_map
GROUP BY event_id, doc_id;
