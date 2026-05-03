with customers as (
    select * from {{ ref('stg_customers') }}
),

orders as (
    select * from {{ ref('int_orders_complete') }}
)

-- Aggregate order stats to the true-customer grain (customer_unique_id)
select
    c.customer_unique_id,
    count(o.order_id)                   as total_orders,
    coalesce(
        sum(o.total_payment_value), 0.00
    )                                   as lifetime_value,
    min(o.order_purchase_timestamp)     as first_order_date,
    max(o.order_purchase_timestamp)     as last_order_date

from customers as c
left join orders as o
    on c.customer_id = o.customer_id
group by c.customer_unique_id
