-- Every line item must link to a valid product in dim_products (referential integrity).
select
    f.order_id,
    f.order_item_id,
    f.product_key
from {{ ref('fct_order_items') }} as f
left join {{ ref('dim_products') }} as d
    on f.product_key = d.product_key
where d.product_key is null
