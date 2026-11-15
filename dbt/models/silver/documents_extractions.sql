-- silver.documents_extractions: append-only, ai_query, one row per attempt.
-- Migrated from scripts/silver/sql/05_silver_document_extraction.sql
-- (prompt and response schema unchanged; prompt_version from the dbt variable).
-- NEVER rebuilt from scratch (full_refresh=false): it holds paid AI results.
-- Incremental: skips doc_id + prompt_version that already have a successful result.
-- NULL metadata is replaced with a default text in the prompt: concat() returns NULL
-- if any argument is NULL, and a NULL prompt would be stored as a 'successful' empty
-- result that is never retried.
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    full_refresh=false
) }}
{{ ai_full_run_guard() }}

WITH candidates AS (
  SELECT c.doc_id,
         c.clean_text,
         c.language,
         m.publish_date,
         m.primary_company
  FROM {{ source('silver_legacy', 'documents_clean') }} c
  JOIN {{ source('silver_legacy', 'documents') }} m   ON m.doc_id = c.doc_id
  JOIN {{ ref('documents_relevance') }} rel           ON rel.doc_id = c.doc_id
  WHERE rel.is_relevant
  {% if is_incremental() %}
    AND NOT EXISTS (SELECT 1 FROM {{ this }} e
                    WHERE e.doc_id = c.doc_id
                      AND e.prompt_version = '{{ var("prompt_version") }}'
                      AND e.ai_error IS NULL
                      AND e.ai_raw_json IS NOT NULL)
  {% endif %}
  {{ ai_sample_limit() }}
),
extracted AS (
  SELECT d.doc_id,
         ai_query(
           'databricks-gpt-oss-120b',
           concat(
             'You extract humanoid-robotics industry events from a news article or press release.\n',
             'Rules:\n',
             '- Only extract information explicitly stated in the text. If unsure, use null.\n',
             '- One article can contain 0 to many events. Return an empty array if there are none.\n',
             '- event_date: only a date explicitly stated for the event; otherwise null. ',
               'Use publish_date to resolve relative dates such as last month.\n',
             '- region = where the event takes place, not where the company is headquartered.\n',
             '- amount: plain number (1 billion = 1000000000) with ISO currency code.\n',
             '- Company names: standard English name in name; original-script name in name_original.\n',
             '- evidence_quote: copy one sentence from the text verbatim. Do not translate it.\n',
             '- summary_en: 2-3 sentences in English, even if the text is Chinese.\n',
             '\n[publish_date] ', coalesce(cast(d.publish_date AS STRING), 'unknown'),
             '\n[language] ', coalesce(d.language, 'unknown'),
             '\n[primary_company] ', coalesce(d.primary_company, 'none'),
             '\n\n[text]\n', d.clean_text
           ),
           responseFormat => '{
             "type": "json_schema",
             "json_schema": {
               "name": "doc_events",
               "strict": true,
               "schema": {
                 "type": "object",
                 "properties": {
                   "summary_en": {"type": "string"},
                   "events": {
                     "type": "array",
                     "items": {
                       "type": "object",
                       "properties": {
                         "event_type": {"type": "string",
                           "enum": ["funding","partnership","product_launch","production_plan","policy","other"]},
                         "status": {"type": "string", "enum": ["announced","planned","completed"]},
                         "event_date": {"type": ["string","null"], "description": "YYYY-MM-DD, only if explicitly stated"},
                         "companies": {
                           "type": "array",
                           "items": {
                             "type": "object",
                             "properties": {
                               "name": {"type": "string", "description": "Standard English name"},
                               "name_original": {"type": ["string","null"], "description": "Name as written in source"},
                               "role": {"type": "string",
                                 "enum": ["investor","target","partner","customer","supplier","issuer"]}
                             },
                             "required": ["name","name_original","role"],
                             "additionalProperties": false
                           }
                         },
                         "technology_areas": {"type": "array", "items": {"type": "string",
                           "enum": ["sensors","compute_electronics","software_ai","actuators","battery_power","not_specified"]}},
                         "components": {"type": "array", "items": {"type": "string"}},
                         "application_sector": {"type": "string",
                           "enum": ["automotive_manufacturing","logistics_warehouse","industrial_other",
                                    "household","healthcare","research_education","not_specified"]},
                         "region": {"type": "string",
                           "enum": ["Europe","North America","China","Asia_other","Global","not_specified"]},
                         "amount": {"type": ["number","null"]},
                         "currency": {"type": ["string","null"], "description": "ISO 4217 code"},
                         "quantity": {"type": ["number","null"]},
                         "quantity_unit": {"type": ["string","null"], "description": "units or units_per_year"},
                         "evidence_quote": {"type": "string", "description": "One sentence copied verbatim"}
                       },
                       "required": ["event_type","status","event_date","companies","technology_areas","components",
                                    "application_sector","region","amount","currency","quantity","quantity_unit",
                                    "evidence_quote"],
                       "additionalProperties": false
                     }
                   }
                 },
                 "required": ["summary_en","events"],
                 "additionalProperties": false
               }
             }
           }',
           failOnError => false
         ) AS r
  FROM candidates d
)
SELECT doc_id,
       '{{ var("prompt_version") }}'  AS prompt_version,
       'databricks-gpt-oss-120b'      AS model_name,
       r.result                       AS ai_raw_json,
       r.errorMessage                 AS ai_error,
       current_timestamp()            AS extracted_at
FROM extracted
