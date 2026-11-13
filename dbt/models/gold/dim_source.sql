-- gold.dim_source: one row per source document.
-- Migrated from scripts/gold/sql/03_gold_dim_source.sql (logic unchanged).
-- Materialization (table) and schema (gold) are set in dbt_project.yml.

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
FROM {{ source('silver_legacy', 'documents') }} d
LEFT JOIN {{ source('silver_legacy', 'document_summaries') }} s
  ON s.doc_id = d.doc_id
