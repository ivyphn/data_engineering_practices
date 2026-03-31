SELECT
    row_number() over (order by order_status) as id,
    order_status                              as description
FROM (
    SELECT distinct order_status
    FROM {{ source('ol', 'orders') }}
    WHERE order_status is not null
);