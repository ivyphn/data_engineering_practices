SELECT product_id
FROM {{ ref('my_products') }}
group by product_id
having count(1) > 1 or product_id is null