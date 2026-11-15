{#
  Safety macros for models that call AI functions (paid, rate-limited).

  ai_full_run_guard(): stops the run when an AI model would be built from
  scratch, i.e. its table does not exist yet in the target schema. Without the
  guard, dbt would send EVERY document to the AI on the first build in a new
  schema (dev_silver, ci_silver). Use clone_ai_tables_from_prod first, or
  pass --vars '{allow_ai_full_run: true}' on purpose, or sample_only for CI.

  ai_sample_limit(): with --vars '{sample_only: true}', only sample_size
  documents (default 5) are sent to the AI. Used by CI.
#}

{% macro ai_full_run_guard() %}
  {% if execute
        and not is_incremental()
        and not var('allow_ai_full_run', false)
        and not var('sample_only', false) %}
    {{ exceptions.raise_compiler_error(
        "Model '" ~ this ~ "' calls AI functions and its table does not exist yet, "
        ~ "so dbt would send ALL documents to the AI. "
        ~ "Run 'dbt run-operation clone_ai_tables_from_prod' first (dev), "
        ~ "use --vars '{sample_only: true}' (CI), "
        ~ "or pass --vars '{allow_ai_full_run: true}' if a full run is really intended."
    ) }}
  {% endif %}
{% endmacro %}

{% macro ai_sample_limit() %}
  {%- if var('sample_only', false) -%}
  LIMIT {{ var('sample_size', 5) }}
  {%- endif -%}
{% endmacro %}

{#
  dbt run-operation clone_ai_tables_from_prod
  Creates the append-only AI tables in the current (non-prod) silver schema as
  SHALLOW CLONEs of the prod tables: no data files are copied and no AI is called.
  Existing tables are left as they are (IF NOT EXISTS).
#}
{% macro clone_ai_tables_from_prod() %}
  {% if target.name == 'prod' %}
    {{ exceptions.raise_compiler_error("clone_ai_tables_from_prod must not run against prod.") }}
  {% endif %}
  {% set catalog = target.database %}
  {% set schema = generate_schema_name('silver', none) %}
  {% do run_query("CREATE SCHEMA IF NOT EXISTS " ~ catalog ~ "." ~ schema) %}
  {% for t in ['documents_relevance', 'documents_extractions'] %}
    {% set sql -%}
      CREATE TABLE IF NOT EXISTS {{ catalog }}.{{ schema }}.{{ t }}
      SHALLOW CLONE {{ catalog }}.silver.{{ t }}
    {%- endset %}
    {% do run_query(sql) %}
    {{ log("ok: " ~ catalog ~ "." ~ schema ~ "." ~ t ~ " (shallow clone of " ~ catalog ~ ".silver." ~ t ~ ")", info=True) }}
  {% endfor %}
{% endmacro %}
