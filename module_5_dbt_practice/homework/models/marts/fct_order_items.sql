with order_items as (
    select * from {{ ref('stg_order_items') }}
)

select
    -- grain: one row per (order_id, order_item_id)
    order_id,
    order_item_id,

    -- foreign keys to dimensions
    product_id              as product_key,
    seller_id               as seller_key,

    -- measures
    price,
    freight_value,
    price + freight_value   as total_item_value,

    -- logistics
    shipping_limit_date

from order_items
