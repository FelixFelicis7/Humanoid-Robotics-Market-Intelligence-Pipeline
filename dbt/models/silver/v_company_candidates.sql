-- silver.v_company_candidates: extracted company names that match neither a
-- company_name nor an alias. Review after each batch (BR-CO-05).
-- Migrated from scripts/silver/sql/07_company_candidates.sql (logic unchanged).
-- Review query: SELECT * FROM <schema>.v_company_candidates ORDER BY company_name
{{ config(materialized='view') }}

WITH extracted_company AS (
  SELECT
    upper(trim(c.name))  AS name_upper,
    mode(trim(c.name))   AS company_name
  FROM {{ ref('events_extracted') }} e
  LATERAL VIEW explode(e.companies) t AS c
  WHERE c.name IS NOT NULL AND trim(c.name) <> ''
  GROUP BY upper(trim(c.name))
)
SELECT
  lower(regexp_replace(x.company_name, '[^A-Za-z0-9]+', '_')) AS company_id,
  x.company_name
FROM extracted_company x
LEFT ANTI JOIN (
  SELECT upper(trim(company_name)) AS name_key FROM {{ source('silver_legacy', 'company') }}
  UNION
  SELECT upper(trim(alias)) FROM {{ source('silver_legacy', 'company_alias') }}
) k ON k.name_key = x.name_upper
