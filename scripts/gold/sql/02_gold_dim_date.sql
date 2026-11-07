-- =====================================================================
-- gold.dim_date
-- Converted from: scripts/gold/02_gold_dim_date.ipynb (original kept unchanged)
-- Reads: (generated, no source table)
-- Job task: gold_dim_date (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.dim_date AS
SELECT
  date,
  year(date)                              AS year,
  quarter(date)                           AS quarter,
  month(date)                             AS month,
  date_format(date, 'yyyy-MM')            AS year_month,
  concat(year(date), '-Q', quarter(date)) AS year_quarter
FROM (
  SELECT explode(sequence(DATE'2020-01-01', DATE'2030-12-31', INTERVAL 1 DAY)) AS date
);
