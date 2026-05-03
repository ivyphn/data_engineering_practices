with source as (
    select * from {{ ref('olist_orders') }}
)

select
    order_id,
    customer_id,
    order_status,
    {{ convert_timezone('order_purchase_timestamp') }}       as order_purchase_timestamp,
    {{ convert_timezone('order_approved_at') }}              as order_approved_at,
    {{ convert_timezone('order_delivered_carrier_date') }}   as order_delivered_carrier_date,
    {{ convert_timezone('order_delivered_customer_date') }}  as order_delivered_customer_date,
    {{ convert_timezone('order_estimated_delivery_date') }}  as order_estimated_delivery_date

from source
