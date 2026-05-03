with orders_items as (
    select * from {{ ref('int_orders_items_agg') }}
),

payments as (
    select * from {{ ref('int_orders_payments_agg') }}
),

reviews as (
    select * from {{ ref('int_orders_reviews_agg') }}
)

select
    -- order identifiers
    oi.order_id,
    oi.customer_id,
    oi.order_status,

    -- timestamps
    oi.order_purchase_timestamp,
    oi.order_approved_at,
    oi.order_delivered_carrier_date,
    oi.order_delivered_customer_date,
    oi.order_estimated_delivery_date,

    -- delivery lead times (days)
    {{ datediff_days('oi.order_purchase_timestamp', 'oi.order_delivered_customer_date') }}
        as actual_delivery_days,
    {{ datediff_days('oi.order_purchase_timestamp', 'oi.order_estimated_delivery_date') }}
        as estimated_delivery_days,

    -- item metrics
    oi.item_count,
    oi.subtotal,
    oi.total_freight,

    -- payment metrics
    coalesce(p.total_payment_value, 0.00)   as total_payment_value,
    p.primary_payment_type,
    p.max_installments,
    coalesce(p.payment_method_count, 1)     as payment_method_count,
    coalesce(p.payment_split_flag, false)   as payment_split_flag,

    -- review metrics
    r.avg_review_score,
    r.max_review_score,
    r.review_count,
    r.latest_comment,
    case when r.avg_review_score is not null
         then true else false
    end                                     as has_review,

    -- delivery classification
    case
        when oi.order_status = 'canceled'
            then 'cancelled'
        when oi.order_status = 'delivered'
             and oi.order_delivered_customer_date is not null
             and oi.order_delivered_customer_date <= oi.order_estimated_delivery_date
            then 'on_time'
        when oi.order_status = 'delivered'
             and oi.order_delivered_customer_date is not null
             and oi.order_delivered_customer_date > oi.order_estimated_delivery_date
            then 'late'
        when oi.order_status in ('shipped', 'invoiced', 'processing', 'approved', 'created')
            then 'in_transit'
        else 'unknown'
    end                                     as delivery_status,
    case
        when oi.order_status = 'delivered'
             and oi.order_delivered_customer_date is not null
             and oi.order_delivered_customer_date > oi.order_estimated_delivery_date
        then true else false
    end                                     as is_late_delivery

from orders_items as oi
left join payments as p
    on oi.order_id = p.order_id
left join reviews as r
    on oi.order_id = r.order_id
