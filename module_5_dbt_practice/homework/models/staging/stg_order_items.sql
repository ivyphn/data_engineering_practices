with source as (
    select * from {{ ref('olist_order_items') }}
)

select
    order_id,
    cast(order_item_id as int)                              as order_item_id,
    product_id,
    seller_id,
    cast(price as decimal(10, 2))                           as price,
    cast(freight_value as decimal(10, 2))                   as freight_value,
    {{ convert_timezone('shipping_limit_date') }}           as shipping_limit_date

from source
