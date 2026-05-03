with customers as (
    select
        customer_unique_id,
        customer_id
    from {{ ref('stg_customers') }}
),

orders as (
    select
        order_id,
        customer_id,
        total_payment_value,
        order_purchase_timestamp
    from {{ ref('int_orders_complete') }}
    where order_status = 'delivered'
),

-- Determine the acquisition month for every unique customer
customer_acquisition as (
    select
        c.customer_unique_id,
        date_trunc(
            'month',
            date(min(o.order_purchase_timestamp))
        )                               as acquisition_month
    from customers as c
    inner join orders as o
        on c.customer_id = o.customer_id
    group by c.customer_unique_id
),

-- Size of each acquisition cohort (number of new customers that month)
cohort_sizes as (
    select
        acquisition_month,
        count(distinct customer_unique_id) as cohort_size
    from customer_acquisition
    group by acquisition_month
),

-- Map every subsequent order back to the customer's acquisition cohort
customer_activity as (
    select
        ca.customer_unique_id,
        ca.acquisition_month,
        date_trunc(
            'month',
            date(o.order_purchase_timestamp)
        )                               as activity_month,
        o.total_payment_value
    from customer_acquisition as ca
    inner join customers as c
        on ca.customer_unique_id = c.customer_unique_id
    inner join orders as o
        on c.customer_id = o.customer_id
)

select
    a.acquisition_month,
    a.activity_month,
    date_diff('month', a.acquisition_month, a.activity_month) as months_since_acquisition,
    cs.cohort_size,

    -- how many customers from this cohort placed at least one order this month
    count(distinct a.customer_unique_id)                as active_customers,

    -- retention rate = active / cohort size
    round(
        cast(count(distinct a.customer_unique_id) as double)
        / nullif(cs.cohort_size, 0),
        4
    )                                                   as retention_rate,

    -- order volume & revenue for this cohort in this month
    count(*)                                            as total_orders,
    sum(a.total_payment_value)                          as total_revenue,
    round(avg(a.total_payment_value), 2)                as avg_order_value

from customer_activity as a
inner join cohort_sizes as cs
    on a.acquisition_month = cs.acquisition_month
group by
    a.acquisition_month,
    a.activity_month,
    cs.cohort_size
