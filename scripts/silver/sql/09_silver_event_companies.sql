-- =====================================================================
-- silver.event_companies
-- Converted from: scripts/silver/09_silver_event_companies.dbquery.ipynb (original kept in sync)
-- Reads: silver.events_extracted, silver.company, silver.company_alias
-- Job task: silver_09_event_companies (SQL file)
-- Name matching (BR-CO-04): an extracted name matches a company when
-- upper(trim()) equals its company_name OR one of its aliases.
-- An alias must point to exactly one company (checked in 12, Check 6).
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
LEFT JOIN (
  SELECT upper(trim(company_name)) AS name_key, company_id FROM humanoid_robotics.silver.company
  UNION
  SELECT upper(trim(alias)), company_id FROM humanoid_robotics.silver.company_alias
) k ON k.name_key = upper(ed.company_name_raw)
LEFT JOIN humanoid_robotics.silver.company co
       ON co.company_id = k.company_id

QUALIFY row_number() OVER (
          PARTITION BY ed.event_id,
                       coalesce(co.company_id, upper(ed.company_name_raw)),
                       ed.role
          ORDER BY ed.company_pos) = 1;
