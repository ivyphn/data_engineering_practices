-- Every line item must link to a valid seller in dim_sellers (referential integrity).
select
    f.order_id,
    f.order_item_id,
    f.seller_key
from {{ ref('fct_order_items') }} as f
left join {{ ref('dim_sellers') }} as d
    on f.seller_key = d.seller_key
where d.seller_key is null
