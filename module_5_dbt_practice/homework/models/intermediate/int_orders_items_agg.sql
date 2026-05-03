with orders as (
    select * from {{ ref('stg_orders') }}
),

items_agg as (
    select
        order_id,
        count(*)                        as item_count,
        sum(price)                      as subtotal,
        sum(freight_value)              as total_freight
    from {{ ref('stg_order_items') }}
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    coalesce(i.item_count, 0)           as item_count,
    coalesce(i.subtotal, 0.00)          as subtotal,
    coalesce(i.total_freight, 0.00)     as total_freight

from orders as o
left join items_agg as i
    on o.order_id = i.order_id
