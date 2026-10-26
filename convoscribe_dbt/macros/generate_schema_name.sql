-- By default dbt names schemas like "main_staging" (target schema + custom schema).
-- This standard override uses the custom schema name as-is, so our schemas are
-- simply "staging", "intermediate" and "marts".
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}