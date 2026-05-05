-- Every payment must have a positive value. Zero or negative values indicate bad source data.
select
    order_id,
    payment_sequential,
    payment_value
from {{ ref('stg_order_payments') }}
where payment_value < 0
