-- A name (company_name or alias) must point to exactly one company,
-- otherwise event_companies gets duplicate rows for the same extracted name.
-- Was: 12_silver_quality_check check 6a.
WITH name_keys AS (
  SELECT upper(trim(company_name)) AS name_key, company_id FROM {{ source('silver_legacy', 'company') }}
  UNION
  SELECT upper(trim(alias)), company_id FROM {{ source('silver_legacy', 'company_alias') }}
)
SELECT name_key, collect_set(company_id) AS company_ids
FROM name_keys
GROUP BY name_key
HAVING count(DISTINCT company_id) > 1
