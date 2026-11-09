-- =====================================================================
-- gold.bridge_event_company
-- Converted from: scripts/gold/06_gold_bridge_event_company.ipynb (original kept in sync)
-- Reads: silver.event_companies, silver.event_dedup_map
-- Job task: gold_bridge_event_company (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.bridge_event_company AS
SELECT DISTINCT
  m.event_id,
  ec.company_id,
  ec.role               -- target / issuer / investor / customer / supplier / partner
FROM humanoid_robotics.silver.event_companies ec
JOIN humanoid_robotics.silver.event_dedup_map m
  ON m.extracted_event_id = ec.event_id      
WHERE ec.company_id IS NOT NULL;
