{#
  Schema naming rule.
  - prod target: use the layer name as is (gold, silver), so Genie, RAG and
    metric views keep reading the same schemas as before dbt.
  - any other target (dev, ci): prefix with the target schema, e.g. dev_gold.
  dbt's default would be <target_schema>_<layer> for every target (prod_gold).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
