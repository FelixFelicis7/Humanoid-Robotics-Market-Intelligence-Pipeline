-- silver.event_companies: one row per event x company x role, matched to the company table.
-- Migrated from scripts/silver/sql/09_silver_event_companies.sql (logic unchanged).
-- Matching rule: company_name OR alias (BR-CO-04); same rule as v_company_candidates.

WITH exploded AS (
  SELECT e.event_id,
         e.doc_id,
         t.pos                     AS company_pos,
         trim(t.c.name)            AS company_name_raw,
         t.c.name_original,
         lower(trim(t.c.role))     AS role
  FROM {{ ref('events_extracted') }} e
  LATERAL VIEW posexplode(e.companies) t AS pos, c
  WHERE t.c.name IS NOT NULL AND trim(t.c.name) <> ''
)
SELECT ed.event_id,
       ed.doc_id,
       ed.company_pos,
       ed.company_name_raw,
       ed.name_original,
       ed.role,
       co.company_id,
       co.company_name             AS company_name_std,
       co.company_id IS NOT NULL   AS is_matched
FROM exploded ed
LEFT JOIN (
  SELECT upper(trim(company_name)) AS name_key, company_id FROM {{ source('silver_legacy', 'company') }}
  UNION
  SELECT upper(trim(alias)), company_id FROM {{ source('silver_legacy', 'company_alias') }}
) k ON k.name_key = upper(ed.company_name_raw)
LEFT JOIN {{ source('silver_legacy', 'company') }} co
       ON co.company_id = k.company_id
QUALIFY row_number() OVER (
          PARTITION BY ed.event_id,
                       coalesce(co.company_id, upper(ed.company_name_raw)),
                       ed.role
          ORDER BY ed.company_pos) = 1
