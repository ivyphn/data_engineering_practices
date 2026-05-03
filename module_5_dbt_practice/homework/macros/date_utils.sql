{% macro convert_timezone(column_name, tz='Australia/Adelaide') %}
    {#
        Converts a timestamp column to the specified timezone and returns
        a formatted string 'YYYY-MM-DD HH:MM:SS'. NULL-safe.

        Args:
            column_name: Column expression to convert (unquoted).
            tz:          IANA timezone string. Defaults to 'Australia/Adelaide'.

        Usage:
            {{ convert_timezone('order_purchase_timestamp') }}
            {{ convert_timezone('event_time', 'Australia/Sydney') }}
    #}
    CASE
        WHEN {{ column_name }} IS NULL THEN NULL
        ELSE date_format(
            CAST({{ column_name }} AT TIME ZONE '{{ tz }}' AS timestamp),
            '%Y-%m-%d %H:%i:%s'
        )
    END
{% endmacro %}


{% macro date_part(part, column_name) %}
    {#
        Extracts a date part from a date/timestamp column using Athena-compatible
        Presto functions. More readable than writing extract() everywhere.

        Supported parts: year, month, day, quarter, hour, minute, dow (day of week)

        Usage:
            {{ date_part('year', 'order_purchase_timestamp') }}
    #}
    {%- if part == 'dow' -%}
        day_of_week({{ column_name }})
    {%- else -%}
        {{ part }}({{ column_name }})
    {%- endif -%}
{% endmacro %}


{% macro datediff_days(start_col, end_col) %}
    {#
        Returns the number of days between two date/timestamp columns.
        Returns NULL if either input is NULL.

        Usage:
            {{ datediff_days('order_purchase_timestamp', 'order_delivered_customer_date') }}
    #}
    CASE
        WHEN {{ start_col }} IS NULL OR {{ end_col }} IS NULL THEN NULL
        ELSE date_diff('day', date({{ start_col }}), date({{ end_col }}))
    END
{% endmacro %}
