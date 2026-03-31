SELECT 
    o.order_id, 
    c.id                      as customer_id,
    d.id                      as order_status_id, 
    cal_purchase.date_key     as purchase_dt,
    cal_approved.date_key     as approved_dt,
    cal_carrier.date_key      as carrier_dt,
    cal_customer.date_key     as customer_dt,
    cal_estimated.date_key    as est_delivery_dt
FROM {{ source('ol', 'orders') }} o
LEFT JOIN {{ ref('vw_dim_order_status') }} d
    ON o.order_status = d.description
LEFT JOIN {{ ref('vw_dim_customer') }} c
    ON o.customer_id = c.customer_string
LEFT JOIN {{ ref('vw_dim_calendar') }} cal_purchase
    ON cast(date_format(from_unixtime(o.order_purchase_timestamp / 1000000000), '%Y%m%d') as integer) = cal_purchase.date_key
LEFT JOIN {{ ref('vw_dim_calendar') }} cal_approved
    ON cast(date_format(from_unixtime(o.order_approved_at / 1000000000), '%Y%m%d') as integer) = cal_approved.date_key
LEFT JOIN {{ ref('vw_dim_calendar') }} cal_carrier
    ON cast(date_format(from_unixtime(o.order_delivered_carrier_date / 1000000000), '%Y%m%d') as integer) = cal_carrier.date_key
LEFT JOIN {{ ref('vw_dim_calendar') }} cal_customer
    ON cast(date_format(from_unixtime(o.order_delivered_customer_date / 1000000000), '%Y%m%d') as integer) = cal_customer.date_key
LEFT JOIN {{ ref('vw_dim_calendar') }} cal_estimated
    ON cast(date_format(from_unixtime(o.order_estimated_delivery_date / 1000000000), '%Y%m%d') as integer) = cal_estimated.date_key
WHERE o.order_status is not null