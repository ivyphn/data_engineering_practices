-- A delivered order's actual delivery date must not be before the purchase date.
-- A negative delivery window means the data is corrupted.
select
    order_id,
    order_purchase_timestamp,
    order_delivered_customer_date
from {{ ref('int_orders_complete') }}
where order_delivered_customer_date is not null
  and date(order_delivered_customer_date) < date(order_purchase_timestamp)
