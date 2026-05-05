-- An order's total payment value must never be negative.
select
    order_id,
    total_payment_value
from {{ ref('int_orders_payments_agg') }}
where total_payment_value < 0
