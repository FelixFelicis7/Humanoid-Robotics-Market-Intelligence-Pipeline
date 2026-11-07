-- =====================================================================
-- silver.event_companies
-- Converted from: scripts/silver/09_silver_event_companies.dbquery.ipynb (original kept unchanged)
-- Reads: silver.events_extracted, silver.company
-- Job task: silver_09_event_companies (SQL file)
-- =====================================================================

CREATE OR REPLACE TABLE humanoid_robotics.silver.event_companies AS
WITH exploded AS (
  SELECT e.event_id,
         e.doc_id,
         t.pos                     AS company_pos,
         trim(t.c.name)            AS company_name_raw,
         t.c.name_original,
         lower(trim(t.c.role))     AS role
  FROM humanoid_robotics.silver.events_extracted e
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
LEFT JOIN humanoid_robotics.silver.company co
       ON upper(trim(co.company_name)) = upper(ed.company_name_raw)

QUALIFY row_number() OVER (
          PARTITION BY ed.event_id,
                       coalesce(co.company_id, upper(ed.company_name_raw)),
                       ed.role
          ORDER BY ed.company_pos) = 1;
