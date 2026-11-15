-- silver.v_extractions_parsed: latest successful AI extraction per document, JSON parsed.
-- Migrated from scripts/silver/sql/06_silver_extraction_parse.sql (logic unchanged).
-- prompt_version comes from the dbt variable (dbt_project.yml), was hard-coded 'v1'.
{{ config(materialized='view') }}

SELECT doc_id, prompt_version, model_name, extracted_at,
       from_json(ai_raw_json,
         'STRUCT<summary_en: STRING,
                 events: ARRAY<STRUCT<
                   event_type: STRING, status: STRING, event_date: STRING,
                   companies: ARRAY<STRUCT<name: STRING, name_original: STRING, role: STRING>>,
                   technology_areas: ARRAY<STRING>, components: ARRAY<STRING>,
                   application_sector: STRING, region: STRING,
                   amount: DOUBLE, currency: STRING,
                   quantity: DOUBLE, quantity_unit: STRING,
                   evidence_quote: STRING>>>') AS j
FROM {{ source('silver_legacy', 'documents_extractions') }}
WHERE ai_error IS NULL
  AND ai_raw_json IS NOT NULL
  AND prompt_version = '{{ var("prompt_version") }}'
QUALIFY row_number() OVER (PARTITION BY doc_id ORDER BY extracted_at DESC) = 1
