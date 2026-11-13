{#
  Generic test: the combination of columns is unique (composite key).
  Fails with one row per duplicated key. Replaces the
  "count(*) vs count(DISTINCT ...)" checks in 09_gold_bridge_table_quality_checks.
#}
{% test unique_key_combination(model, columns) %}
SELECT {{ columns | join(', ') }}, count(*) AS n_rows
FROM {{ model }}
GROUP BY {{ columns | join(', ') }}
HAVING count(*) > 1
{% endtest %}
