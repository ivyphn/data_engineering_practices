{% test primary_key(model, column_name) %}

    SELECT {{ column_name }}
    FROM {{ model }}
    group by {{ column_name }}
    having count(1) > 1 or {{ column_name }} is null

{% endtest %}