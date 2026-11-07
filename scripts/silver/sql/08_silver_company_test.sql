-- =====================================================================
-- Checks on silver.company and silver.event_companies
-- Converted from: scripts/silver/08_silver_company_test.dbquery.ipynb (original kept unchanged)
-- Reads: silver.events_extracted, silver.company, silver.event_companies
-- Not in the Job: manual checks.
-- =====================================================================

-- 检查 1：事件中出现、但不在 silver.company 里的公司
-- 通过标准：0 行
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
-- 已确认为误抽、不加入公司表的名字（同时记入 prompt_issues.md）
ignored AS (
  SELECT * FROM VALUES
    ('HUMANOID')          -- 待查原文确认后再决定是否保留在这里
  AS t(name_upper)
)
SELECT x.*
FROM extracted x
LEFT JOIN humanoid_robotics.silver.company co
       ON upper(trim(co.company_name)) = x.name_upper
WHERE co.company_id IS NULL
  AND x.name_upper NOT IN (SELECT name_upper FROM ignored)
ORDER BY x.n_mentions DESC, x.name_upper;

SELECT company_id, company_name,
       length(company_name) AS len,
       hex(company_name)    AS hex_name
FROM humanoid_robotics.silver.company
WHERE upper(company_name) LIKE '%UBT%' OR company_name LIKE '%优必选%';

-------------------------------------------------------------
-- 通过标准：total_rows = distinct_ids = distinct_names，且 null_ids = blank_names = 0
SELECT count(*)                                              AS total_rows,
       count(DISTINCT company_id)                            AS distinct_ids,
       count(DISTINCT upper(trim(company_name)))             AS distinct_names,
       count_if(company_id IS NULL)                          AS null_ids,
       count_if(company_name IS NULL OR trim(company_name) = '') AS blank_names
FROM humanoid_robotics.silver.company;

-- Should return 0 rows
SELECT * FROM humanoid_robotics.silver.event_companies WHERE NOT is_matched;
