-- gold.bridge_event_company: event x company x role.
-- Migrated from scripts/gold/sql/06_gold_bridge_event_company.sql (logic unchanged).
-- depends_on: {{ ref('fct_events') }}
-- depends_on: {{ ref('dim_company') }}

SELECT DISTINCT
  m.event_id,
  ec.company_id,
  ec.role               -- target / issuer / investor / customer / supplier / partner
FROM {{ ref('event_companies') }} ec
JOIN {{ ref('event_dedup_map') }} m
  ON m.extracted_event_id = ec.event_id
WHERE ec.company_id IS NOT NULL
