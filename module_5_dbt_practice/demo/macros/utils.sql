{% macro convert_timezone(column_name, tz='Australia/Adelaide') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN NULL
        ELSE date_format(CAST({{ column_name }} AT TIME ZONE '{{ tz }}' AS timestamp), '%Y-%m-%d %H:%i:%s')
    END
{% endmacro %}
