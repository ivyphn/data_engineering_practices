SELECT * 
FROM {{ source('ol', 'products') }}
where product_weight_g >= 45000