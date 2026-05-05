with orders as (
    select * from {{ ref('fct_orders') }}
),

dates as (
    select * from {{ ref('dim_date') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

segments as (
    select * from {{ ref('dim_customer_segments') }}
)

select
    -- order identifiers
    o.order_id,
    o.order_status,
    o.delivery_status,
    o.is_late_delivery,

    -- timestamps
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- date attributes
    d.calendar_date         as purchase_date,
    d.year,
    d.quarter,
    d.month,
    d.is_weekend,
    d.is_business_day,

    -- order measures
    o.item_count,
    o.subtotal,
    o.total_freight,
    o.gross_order_value,
    o.total_payment_value,
    o.actual_delivery_days,
    o.estimated_delivery_days,
    o.delivery_delay_days,

    -- payment
    o.primary_payment_type,
    o.max_installments,
    o.payment_split_flag,

    -- review
    o.avg_review_score,
    o.max_review_score,
    o.review_count,
    o.has_review,

    -- customer attributes
    c.customer_key,
    c.customer_city,
    c.customer_state,
    c.customer_macro_region,
    c.total_orders          as customer_total_orders,
    c.lifetime_value        as customer_lifetime_value,
    c.first_order_date,
    c.last_order_date,

    -- customer segment
    s.customer_segment,
    s.value_tier,
    s.r_score,
    s.f_score,
    s.m_score,
    s.rfm_cell_code

from orders as o
left join dates as d
    on o.purchase_date_key = d.date_key
left join customers as c
    on o.customer_key = c.customer_key
left join segments as s
    on o.customer_key = s.customer_key
