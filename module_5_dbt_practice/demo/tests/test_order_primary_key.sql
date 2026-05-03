SELECT order_id
FROM {{ ref('my_orders') }}
group by order_id
having count(1) > 1 or order_id is null