{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Override dbt's default schema naming so that custom schema names
        are used as-is rather than appended to the target schema.

        Default dbt behaviour:  olist_staging, olist_intermediate, olist_marts
        This macro produces:    staging, intermediate, marts

        Models without a custom_schema_name fall back to target.schema (olist).
    #}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
