select
    {{ dbt_utils.star(from=source('ol', 'orders'), relation_alias='o') }},
    {{ dbt_utils.star(from=source('ol', 'customers'), relation_alias='cust', except=['customer_id']) }}
from {{ source('ol', 'orders') }} as o
left join {{ source('ol', 'customers') }} as cust
    on o.customer_id = cust.customer_id