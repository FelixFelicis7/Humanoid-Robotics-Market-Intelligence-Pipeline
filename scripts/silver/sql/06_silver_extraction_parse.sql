-- =====================================================================
-- silver.v_extractions_parsed (view), silver.document_summaries, silver.events_extracted
-- Converted from: scripts/silver/06_silver_extraction_parse.dbquery.ipynb (original kept unchanged)
-- Reads: silver.documents_extractions, silver.documents
-- Job task: silver_06_extraction_parse (SQL file)
-- Pure SQL, no AI calls: safe to rebuild at any time.
-- Check query moved to sql/12_silver_quality_check.sql.
-- =====================================================================

CREATE OR REPLACE VIEW humanoid_robotics.silver.v_extractions_parsed AS
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
FROM humanoid_robotics.silver.documents_extractions
WHERE ai_error IS NULL
  AND prompt_version = 'v1'     
QUALIFY row_number() OVER (PARTITION BY doc_id ORDER BY extracted_at DESC) = 1;

------------------------------------------------------------------------------
------------------------------------------------------------------------------

CREATE OR REPLACE TABLE humanoid_robotics.silver.document_summaries AS
SELECT 
doc_id, 
j.summary_en, 
size(j.events) AS event_count, 
prompt_version, 
model_name
FROM humanoid_robotics.silver.v_extractions_parsed;

------------------------------------------------------------------------------
------------------------------------------------------------------------------
CREATE OR REPLACE TABLE humanoid_robotics.silver.events_extracted AS
SELECT x.doc_id,
       concat(x.doc_id, '_E', lpad(cast(x.pos +1 AS STRING), 2, '0')) AS event_id,
       CASE WHEN x.ev.event_type IN ('funding', 'partnership', 'product_launch', 'production_plan', 'policy')
            THEN x.ev.event_type
            ELSE 'other'
        END AS event_type,
        x.ev.status,
        coalesce(try_to_date(x. ev.event_date), d.publish_date) AS event_date,
        try_to_date(x.ev.event_date) IS NULL AS date_is_publish_date,
        x.ev.companies,
        x.ev.technology_areas,
        x.ev.components,
        x.ev.application_sector,
        x.ev.region,
        x.ev.amount,
        upper(x.ev.currency) AS currency,
        x.ev.quantity,
        x.ev.quantity_unit,
        x.ev.evidence_quote,
        x.prompt_version
FROM(
    SELECT 
    doc_id,
    prompt_version,
    posexplode(j.events) AS (pos,ev)
    FROM humanoid_robotics.silver.v_extractions_parsed
) x
JOIN humanoid_robotics.silver.documents d ON d.doc_id = x.doc_id;
