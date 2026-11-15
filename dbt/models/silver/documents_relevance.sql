-- silver.documents_relevance: append-only, ai_classify.
-- Migrated from scripts/silver/sql/04_silver_doc_relevance.sql (logic unchanged).
-- NEVER rebuilt from scratch (full_refresh=false): it holds paid AI results.
-- Incremental: only documents without a usable label are sent to ai_classify.
-- A NULL label (failed call or empty input) is kept as a record and retried next run.
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    full_refresh=false
) }}
{{ ai_full_run_guard() }}

WITH candidates AS (
  SELECT d.doc_id,
         d.clean_text
  FROM {{ source('silver_legacy', 'documents_clean') }} d
  {% if is_incremental() %}
  WHERE NOT EXISTS (SELECT 1 FROM {{ this }} r
                    WHERE r.doc_id = d.doc_id
                      AND r.relevance_label IS NOT NULL)
  {% endif %}
  {{ ai_sample_limit() }}
),
labelled AS (
  SELECT doc_id,
         ai_classify(left(clean_text, 4000),
                     ARRAY('about_humanoid_robots', 'not_about_humanoid_robots')) AS label
  FROM candidates
)
SELECT doc_id,
       label                            AS relevance_label,
       label = 'about_humanoid_robots'  AS is_relevant,
       current_timestamp()              AS classified_at
FROM labelled
