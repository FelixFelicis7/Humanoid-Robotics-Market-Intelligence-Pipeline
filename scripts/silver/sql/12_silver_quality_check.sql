-- =====================================================================
-- Silver quality checks
-- Converted from: scripts/silver/12_silver_quality_check.dbquery.ipynb (+ checks moved from 05, 06) (original kept in sync)
-- Reads: silver.company, silver.company_alias, silver.events_extracted, silver.documents_extractions
-- Not in the Job: manual checks.
-- =====================================================================

-- Check 1: Companies that appear in events but match neither a company_name
-- nor an alias (same rule as 09)
-- Pass criterion: 0 rows, apart from names confirmed as not-a-company (ignored list)
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
  -- Names reviewed and deliberately left unmatched (see docs/prompt_issues.md)
  SELECT * FROM VALUES
    ('HUMANOID'),                                                       -- PI-001
    ('MINISTRY OF INDUSTRY AND INFORMATION TECHNOLOGY'),                -- PI-008, government body
    ('STATE-OWNED ASSETS SUPERVISION AND ADMINISTRATION COMMISSION')    -- PI-008, government body
  AS t(name_upper)
),

name_keys AS (
  SELECT upper(trim(company_name)) AS name_key FROM humanoid_robotics.silver.company
  UNION
  SELECT upper(trim(alias)) FROM humanoid_robotics.silver.company_alias
)
SELECT x.*
FROM extracted x
LEFT JOIN name_keys k
       ON k.name_key = x.name_upper
WHERE k.name_key IS NULL
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

-------------------------------------------------------------------
-- Check 5: Incremental AI steps
-- Run before and after a Job run. With no new documents, n and last_ts
-- must not change. With k new documents, n grows by at most k per step.
SELECT 'translations' AS step, count(*) AS n, max(translated_at) AS last_ts FROM humanoid_robotics.silver.document_translations
UNION ALL
SELECT 'relevance',   count(*), max(classified_at) FROM humanoid_robotics.silver.documents_relevance
UNION ALL
SELECT 'extractions', count(*), max(extracted_at)  FROM humanoid_robotics.silver.documents_extractions;

-------------------------------------------------------------------
-- Check 6: Alias table integrity (alias matching is used by 07 and 09)
-- Pass criterion: both queries return 0 rows.
-- 6a: a name (company_name or alias) that points to more than one company.
--     09 would then produce duplicate rows for the same extracted name.
WITH name_keys AS (
  SELECT upper(trim(company_name)) AS name_key, company_id FROM humanoid_robotics.silver.company
  UNION
  SELECT upper(trim(alias)), company_id FROM humanoid_robotics.silver.company_alias
)
SELECT name_key, collect_set(company_id) AS company_ids
FROM name_keys
GROUP BY name_key
HAVING count(DISTINCT company_id) > 1;

-- 6b: an alias whose company_id does not exist in silver.company.
SELECT a.alias, a.company_id
FROM humanoid_robotics.silver.company_alias a
LEFT ANTI JOIN humanoid_robotics.silver.company co
       ON co.company_id = a.company_id;
