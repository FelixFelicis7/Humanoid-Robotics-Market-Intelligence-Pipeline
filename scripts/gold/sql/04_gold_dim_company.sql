-- =====================================================================
-- gold.dim_company
-- Converted from: scripts/gold/04_gold_dim_company.ipynb (original kept in sync)
-- Reads: silver.company
-- Job task: gold_dim_company (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.dim_company AS
SELECT
  company_id,
  company_name,          
  company_name_zh,
  company_type,          -- humanoid_maker / tier1 / investor / customer / technology_partner / other     
  country,
  region
FROM humanoid_robotics.silver.company;
