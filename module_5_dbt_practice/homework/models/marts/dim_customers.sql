with customers_deduped as (
    -- customer_unique_id can map to multiple customer_id rows;
    -- collapse to one row per true customer
    select
        customer_unique_id,
        max(customer_city)  as customer_city,
        max(customer_state) as customer_state
    from {{ ref('stg_customers') }}
    group by customer_unique_id
),

customer_stats as (
    select * from {{ ref('int_customers_orders') }}
),

geography as (
    select state_code, macro_region
    from {{ ref('dim_geography') }}
)

select
    -- surrogate key
    c.customer_unique_id                        as customer_key,

    -- descriptive attributes
    c.customer_city,
    c.customer_state,
    g.macro_region                              as customer_macro_region,

    -- lifetime metrics (pre-computed in intermediate layer)
    coalesce(s.total_orders, 0)                 as total_orders,
    coalesce(s.lifetime_value, 0.00)            as lifetime_value,
    s.first_order_date,
    s.last_order_date

from customers_deduped as c
left join customer_stats as s
    on c.customer_unique_id = s.customer_unique_id
left join geography as g
    on c.customer_state = g.state_code
