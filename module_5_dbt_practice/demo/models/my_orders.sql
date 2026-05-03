SELECT
    order_id,
    customer_id,
    order_status,
    {{ convert_timezone('order_purchase_timestamp') }} AS order_purchase_timestamp,
    {{ convert_timezone('order_approved_at') }} AS order_approved_at,
    {{ convert_timezone('order_delivered_carrier_date') }} AS order_delivered_carrier_date,
    {{ convert_timezone('order_delivered_customer_date') }} AS order_delivered_customer_date,
    {{ convert_timezone('order_estimated_delivery_date') }} AS order_estimated_delivery_date
FROM orders
