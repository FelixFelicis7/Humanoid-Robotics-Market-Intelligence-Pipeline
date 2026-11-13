-- Every event must be linked to at least one source document.
-- Was: 09_gold_bridge_table_quality_checks, check 3 (no_source must be 0).
-- (no_company / no_technology may be > 0, e.g. policy events, so they are not tested.)
SELECT f.event_id
FROM {{ ref('fct_events') }} f
WHERE NOT EXISTS (
  SELECT 1 FROM {{ ref('bridge_event_source') }} b
  WHERE b.event_id = f.event_id
)
