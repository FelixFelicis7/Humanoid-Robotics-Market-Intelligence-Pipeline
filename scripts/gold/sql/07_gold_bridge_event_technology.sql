-- =====================================================================
-- gold.bridge_event_technology
-- Converted from: scripts/gold/07_gold_bridge_event_technology.ipynb (original kept in sync)
-- Reads: silver.events_extracted, silver.event_dedup_map
-- Job task: gold_bridge_event_technology (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.bridge_event_technology AS
SELECT DISTINCT
  m.event_id,
  x.technology_id
FROM (
  SELECT event_id AS extracted_event_id,
         explode(technology_areas) AS technology_id
  FROM humanoid_robotics.silver.events_extracted
) x
JOIN humanoid_robotics.silver.event_dedup_map m
  ON m.extracted_event_id = x.extracted_event_id;
