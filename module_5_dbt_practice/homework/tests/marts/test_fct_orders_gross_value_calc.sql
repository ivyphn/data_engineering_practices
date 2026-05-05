-- gross_order_value must equal subtotal + total_freight. Any discrepancy means
-- the computed column is out of sync with its inputs.
select
    order_id,
    gross_order_value,
    subtotal,
    total_freight,
    subtotal + total_freight as expected_gross_value
from {{ ref('fct_orders') }}
where abs(gross_order_value - (subtotal + total_freight)) > 0.01
