-- gold.dim_company: one row per company.
-- Migrated from scripts/gold/sql/04_gold_dim_company.sql (logic unchanged).

SELECT
  company_id,
  company_name,
  company_name_zh,
  company_type,          -- humanoid_maker / tier1 / investor / customer / technology_partner / other
  country,
  region
FROM {{ source('silver_legacy', 'company') }}
