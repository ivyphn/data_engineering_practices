-- Every segment row must reference a customer that exists in dim_customers.
select
    s.customer_key
from {{ ref('dim_customer_segments') }} as s
left join {{ ref('dim_customers') }} as d
    on s.customer_key = d.customer_key
where d.customer_key is null
