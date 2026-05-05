-- Every order must link to a valid customer in dim_customers (referential integrity).
select
    f.order_id,
    f.customer_key
from {{ ref('fct_orders') }} as f
left join {{ ref('dim_customers') }} as d
    on f.customer_key = d.customer_key
where d.customer_key is null
