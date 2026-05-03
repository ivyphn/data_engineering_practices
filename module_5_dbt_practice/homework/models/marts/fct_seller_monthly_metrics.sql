with order_items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select
        order_id,
        order_status,
        order_purchase_timestamp,
        order_delivered_customer_date,
        order_estimated_delivery_date
    from {{ ref('stg_orders') }}
),

reviews as (
    select
        order_id,
        avg_review_score
    from {{ ref('int_orders_reviews_agg') }}
),

-- Join line items to their order context and reviews
order_item_enriched as (
    select
        oi.seller_id,
        oi.order_id,
        oi.price,
        oi.freight_value,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        r.avg_review_score,
        date_trunc('month', date(o.order_purchase_timestamp)) as order_month
    from order_items as oi
    left join orders as o
        on oi.order_id = o.order_id
    left join reviews as r
        on oi.order_id = r.order_id
)

select
    seller_id                                                   as seller_key,
    order_month,

    -- volume
    count(distinct order_id)                                    as orders_count,
    count(*)                                                    as items_sold,

    -- revenue
    sum(price)                                                  as gmv,
    sum(freight_value)                                          as total_freight_collected,
    round(avg(price), 2)                                        as avg_item_price,

    -- quality
    round(avg(avg_review_score), 2)                             as avg_review_score,

    -- on-time delivery rate (only for delivered orders)
    round(
        cast(
            count(
                case when order_status = 'delivered'
                          and order_delivered_customer_date is not null
                          and order_delivered_customer_date <= order_estimated_delivery_date
                     then 1 end
            ) as double
        ) / nullif(
            count(case when order_status = 'delivered' then 1 end), 0
        ),
        4
    )                                                           as on_time_delivery_rate,

    -- cancellation rate per order (not per item)
    round(
        cast(
            count(distinct case when order_status = 'canceled' then order_id end) as double
        ) / nullif(count(distinct order_id), 0),
        4
    )                                                           as cancellation_rate,

    -- average days from purchase to carrier pickup (fulfilment speed)
    round(
        avg(
            case
                when order_status = 'delivered'
                     and order_delivered_customer_date is not null
                then {{ datediff_days('order_purchase_timestamp', 'order_delivered_customer_date') }}
            end
        ),
        1
    )                                                           as avg_delivery_days

from order_item_enriched
group by seller_id, order_month
