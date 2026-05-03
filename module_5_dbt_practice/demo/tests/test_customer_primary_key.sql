SELECT customer_id
FROM {{ ref('my_customers') }}
group by customer_id
having count(1) > 1 or customer_id is null