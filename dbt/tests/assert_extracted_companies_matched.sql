-- Extracted company names that match neither a company_name nor an alias,
-- apart from names reviewed and deliberately left unmatched.
-- Was: 12_silver_quality_check check 1 (and 08 "Should return 0 rows").
-- severity warn: a new batch normally brings new names. When this warns,
-- review v_company_candidates and update the seeds / aliases.
{{ config(severity='warn') }}

WITH ignored AS (
  -- Keep in sync with docs/prompt_issues.md
  SELECT * FROM VALUES
    ('HUMANOID'),                                                       -- PI-001
    ('MINISTRY OF INDUSTRY AND INFORMATION TECHNOLOGY'),                -- PI-008, government body
    ('STATE-OWNED ASSETS SUPERVISION AND ADMINISTRATION COMMISSION'),   -- PI-008, government body
    ('MINISTRY OF TRADE, INDUSTRY AND ENERGY'),                         -- BR-CO-11, government body (KR)
    ('UNITED STATES CONGRESS')                                          -- BR-CO-11, government body (US)
  AS t(name_upper)
)
SELECT upper(company_name_raw)    AS name_upper,
       max(company_name_raw)      AS name_example,
       collect_set(role)          AS roles,
       count(*)                   AS n_mentions,
       collect_set(doc_id)        AS doc_ids
FROM {{ ref('event_companies') }}
WHERE NOT is_matched
  AND upper(company_name_raw) NOT IN (SELECT name_upper FROM ignored)
GROUP BY upper(company_name_raw)
