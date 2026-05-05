-- Every order's purchase date key must exist in dim_date (referential integrity).
select
    f.order_id,
    f.purchase_date_key
from {{ ref('fct_orders') }} as f
left join {{ ref('dim_date') }} as d
    on f.purchase_date_key = d.date_key
where d.date_key is null
