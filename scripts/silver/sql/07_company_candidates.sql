-- =====================================================================
-- silver.v_company_candidates (view) + review query
-- Converted from: scripts/silver/07_company_candidates.dbquery.ipynb (original kept unchanged)
-- Reads: silver.events_extracted, silver.company, silver.company_alias
-- Uses the same matching rule as 09 (company_name OR alias), so a name
-- that already has an alias does not show up as a candidate.
-- Not in the Job: run manually after each batch and review the result.
-- =====================================================================

CREATE OR REPLACE VIEW humanoid_robotics.silver.v_company_candidates AS
WITH extracted_company AS (
  SELECT
    upper(trim(c.name))  AS name_upper,    
    mode(trim(c.name))   AS company_name    
  FROM humanoid_robotics.silver.events_extracted e
  LATERAL VIEW explode(e.companies) t AS c
  WHERE c.name IS NOT NULL AND trim(c.name) <> ''
  GROUP BY upper(trim(c.name))
)
SELECT
  lower(regexp_replace(x.company_name, '[^A-Za-z0-9]+', '_')) AS company_id,
  x.company_name
FROM extracted_company x
LEFT ANTI JOIN (
  SELECT upper(trim(company_name)) AS name_key FROM humanoid_robotics.silver.company
  UNION
  SELECT upper(trim(alias)) FROM humanoid_robotics.silver.company_alias
) k ON k.name_key = x.name_upper;

SELECT * FROM humanoid_robotics.silver.v_company_candidates ORDER BY company_name;
