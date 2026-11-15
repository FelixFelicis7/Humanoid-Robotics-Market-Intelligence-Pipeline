-- silver.events_extracted: one row per extracted event (before de-duplication).
-- Migrated from scripts/silver/sql/06_silver_extraction_parse.sql (logic unchanged).

SELECT x.doc_id,
       concat(x.doc_id, '_E', lpad(cast(x.pos + 1 AS STRING), 2, '0')) AS event_id,
       CASE WHEN x.ev.event_type IN ('funding', 'partnership', 'product_launch', 'production_plan', 'policy')
            THEN x.ev.event_type
            ELSE 'other'
       END AS event_type,
       x.ev.status,
       coalesce(try_to_date(x.ev.event_date), d.publish_date) AS event_date,
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
FROM (
  SELECT doc_id,
         prompt_version,
         posexplode(j.events) AS (pos, ev)
  FROM {{ ref('v_extractions_parsed') }}
) x
JOIN {{ source('silver_legacy', 'documents') }} d ON d.doc_id = x.doc_id
