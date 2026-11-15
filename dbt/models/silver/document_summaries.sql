-- silver.document_summaries: one row per extracted document (summary + event count).
-- Migrated from scripts/silver/sql/06_silver_extraction_parse.sql (logic unchanged).

SELECT
  doc_id,
  j.summary_en,
  size(j.events) AS event_count,
  prompt_version,
  model_name
FROM {{ ref('v_extractions_parsed') }}
