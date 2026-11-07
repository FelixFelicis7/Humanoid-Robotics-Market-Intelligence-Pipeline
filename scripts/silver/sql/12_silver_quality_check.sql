-- =====================================================================
-- Silver quality checks
-- Converted from: scripts/silver/12_silver_quality_check.dbquery.ipynb (+ checks moved from 05, 06) (original kept unchanged)
-- Reads: silver.company, silver.events_extracted, silver.documents_extractions
-- Not in the Job: manual checks.
-- =====================================================================

-- Check 1: Companies that appear in events but are missing from silver.company
-- Pass criterion: 0 rows
WITH extracted AS (
  SELECT upper(trim(c.name))   AS name_upper,
         max(c.name)           AS name_example,
         max(c.name_original)  AS name_original,
         collect_set(c.role)   AS roles,
         count(*)              AS n_mentions,
         collect_set(e.doc_id) AS doc_ids
  FROM humanoid_robotics.silver.events_extracted e
  LATERAL VIEW explode(e.companies) t AS c
  WHERE c.name IS NOT NULL AND trim(c.name) <> ''
  GROUP BY upper(trim(c.name))
),

ignored AS (
  SELECT * FROM VALUES
    ('HUMANOID')          
  AS t(name_upper)
)
SELECT x.*
FROM extracted x
LEFT JOIN humanoid_robotics.silver.company co
       ON upper(trim(co.company_name)) = x.name_upper
WHERE co.company_id IS NULL
  AND x.name_upper NOT IN (SELECT name_upper FROM ignored)
ORDER BY x.n_mentions DESC, x.name_upper;

-------------------------------------------------------------------
-- Check 2: Uniqueness of silver.company
-- Pass criterion: total_rows = distinct_ids = distinct_names, and null_ids = blank_names = 0

SELECT count(*)                                              AS total_rows,
       count(DISTINCT company_id)                            AS distinct_ids,
       count(DISTINCT upper(trim(company_name)))             AS distinct_names,
       count_if(company_id IS NULL)                          AS null_ids,
       count_if(company_name IS NULL OR trim(company_name) = '') AS blank_names
FROM humanoid_robotics.silver.company;

--- if not, further check which rows
SELECT co.*,
       count(*) OVER (PARTITION BY company_id)                AS n_same_id,
       count(*) OVER (PARTITION BY upper(trim(company_name))) AS n_same_name
FROM humanoid_robotics.silver.company co
QUALIFY n_same_id > 1 OR n_same_name > 1
ORDER BY upper(trim(company_name)), company_id;

-------------------------------------------------------------------
-- Check 3: AI extraction calls that failed (moved from 05)
-- Pass criterion: 0 rows. Failed documents are retried on the next run.
SELECT doc_id, prompt_version, ai_error, extracted_at
FROM humanoid_robotics.silver.documents_extractions
WHERE ai_error IS NOT NULL;

-------------------------------------------------------------------
-- Check 4: Company names as extracted by the AI (moved from 06)
-- Review: spelling variants of the same company, extraction errors
SELECT upper(trim(c.name)) AS name_upper, c.name_original, count(*) AS n
FROM humanoid_robotics.silver.events_extracted
LATERAL VIEW explode(companies) t AS c
GROUP BY ALL
ORDER BY name_upper;
