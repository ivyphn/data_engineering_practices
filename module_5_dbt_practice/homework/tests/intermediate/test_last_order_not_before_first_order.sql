-- A customer's last order date must be on or after their first order date.
select
    customer_unique_id,
    first_order_date,
    last_order_date
from {{ ref('int_customers_orders') }}
where last_order_date is not null
  and first_order_date is not null
  and last_order_date < first_order_date
