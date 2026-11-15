-- Funding events need a company with role target or issuer, otherwise they are
-- missed when funding is summed by company (business rule in metric views / Genie).
-- Was: 09_gold_bridge_table_quality_checks, check 4.
-- severity warn: reported, but does not fail the build. Change to error once clean.
{{ config(severity='warn') }}

SELECT f.event_id, f.amount, f.currency
FROM {{ ref('fct_events') }} f
WHERE f.event_type = 'funding'
  AND NOT EXISTS (
    SELECT 1 FROM {{ ref('bridge_event_company') }} b
    WHERE b.event_id = f.event_id
      AND b.role IN ('target', 'issuer')
  )
