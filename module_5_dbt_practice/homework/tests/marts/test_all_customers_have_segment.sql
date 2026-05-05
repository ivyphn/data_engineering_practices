-- Every customer in dim_customers must have a corresponding row in dim_customer_segments.
-- A missing segment means the RFM model did not cover all customers.
select
    d.customer_key
from {{ ref('dim_customers') }} as d
left join {{ ref('dim_customer_segments') }} as s
    on d.customer_key = s.customer_key
where s.customer_key is null
