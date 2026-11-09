-- =====================================================================
-- gold.dim_source
-- Converted from: scripts/gold/03_gold_dim_source.ipynb (original kept in sync)
-- Reads: silver.documents, silver.document_summaries
-- Job task: gold_dim_source (SQL file)
-- Was: spark.sql(query) + write.mode("overwrite").saveAsTable(...)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.gold.dim_source AS
SELECT
  d.doc_id,
  d.title,
  d.publisher,
  d.source_type,          -- press_release / filing / news / policy
  d.language,             -- en / zh
  d.publish_date,
  d.url,
  d.primary_company,      
  s.summary_en,
  coalesce(s.event_count, 0) AS event_count
FROM humanoid_robotics.silver.documents d
LEFT JOIN humanoid_robotics.silver.document_summaries s
  ON s.doc_id = d.doc_id;
