{#
  Informational PK / FK constraints for gold tables (replaces
  scripts/gold/sql/99_gold_constraints.sql). Used as post-hooks in
  models/gold/schema.yml, so they run right after each table is rebuilt.
  Each macro returns ONE statement, because each hook is sent as one query.

  Order of hooks per table: drop old PK (CASCADE also drops FKs in other
  tables that point to it; those tables are rebuilt later in the same run
  and add their FKs again) -> NOT NULL on key columns -> add PK -> add FKs.
  A model that adds an FK must declare its parent with
  "-- depends_on: {{ ref('parent') }}" so the parent is built first.
#}

{% macro drop_primary_key() -%}
ALTER TABLE {{ this }} DROP PRIMARY KEY IF EXISTS CASCADE
{%- endmacro %}

{% macro set_not_null(column) -%}
ALTER TABLE {{ this }} ALTER COLUMN {{ column }} SET NOT NULL
{%- endmacro %}

{% macro add_primary_key(name, columns) -%}
ALTER TABLE {{ this }} ADD CONSTRAINT {{ name }} PRIMARY KEY ({{ columns | join(', ') }})
{%- endmacro %}

{% macro drop_constraint(name) -%}
ALTER TABLE {{ this }} DROP CONSTRAINT IF EXISTS {{ name }}
{%- endmacro %}

{% macro add_foreign_key(name, column, parent, parent_column) -%}
ALTER TABLE {{ this }} ADD CONSTRAINT {{ name }} FOREIGN KEY ({{ column }}) REFERENCES {{ parent }} ({{ parent_column }})
{%- endmacro %}
