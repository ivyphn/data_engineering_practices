-- The estimated delivery date must be on or after the purchase date.
-- Sellers cannot promise delivery before the order is placed.
select
    order_id,
    order_purchase_timestamp,
    order_estimated_delivery_date
from {{ ref('int_orders_complete') }}
where order_estimated_delivery_date is not null
  and date(order_estimated_delivery_date) < date(order_purchase_timestamp)
