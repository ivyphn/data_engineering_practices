with orders as (
    select * from {{ ref('int_orders_complete') }}
),

customers as (
    -- Resolve order-scoped customer_id to the true customer_unique_id
    select
        customer_id,
        customer_unique_id
    from {{ ref('stg_customers') }}
)

select
    -- grain: one row per order
    o.order_id,

    -- foreign keys to dimensions
    c.customer_unique_id                                            as customer_key,
    cast(date_format(
        date(o.order_purchase_timestamp), '%Y%m%d'
    ) as int)                                                       as purchase_date_key,

    -- order lifecycle status
    o.order_status,

    -- timestamps
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- delivery metrics
    o.actual_delivery_days,
    o.estimated_delivery_days,
    {{ datediff_days('o.order_delivered_customer_date',
                     'o.order_estimated_delivery_date') }}          as delivery_delay_days,

    -- item measures
    o.item_count,
    o.subtotal,
    o.total_freight,
    o.subtotal + o.total_freight                                    as gross_order_value,

    -- payment measures
    o.total_payment_value,
    o.primary_payment_type,
    o.max_installments,
    o.payment_method_count,
    o.payment_split_flag,

    -- review measures
    o.avg_review_score,
    o.max_review_score,
    o.review_count,
    o.has_review,

    -- delivery classification
    o.delivery_status,
    o.is_late_delivery

from orders as o
left join customers as c
    on o.customer_id = c.customer_id
