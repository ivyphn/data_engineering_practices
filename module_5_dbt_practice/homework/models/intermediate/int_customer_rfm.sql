with customer_metrics as (
    select * from {{ ref('int_customers_orders') }}
    where last_order_date is not null
),

-- Use the latest order date in the dataset as the recency anchor.
-- This keeps scores stable and comparable across all customers.

reference_date as (
    select max(date(last_order_date)) as anchor_date
    from customer_metrics
),

rfm_base as (
    select
        c.customer_unique_id,
        date_diff(
            'day',
            date(c.last_order_date),
            r.anchor_date
        )                               as recency_days,
        c.total_orders                  as frequency,
        c.lifetime_value                as monetary
    from customer_metrics as c
    cross join reference_date as r
),

rfm_scores as (
    select
        customer_unique_id,
        recency_days,
        frequency,
        monetary,

        -- R: fewer days since last order = more recent = higher score
        ntile(5) over (order by recency_days desc)  as r_score,
        -- F: more orders = higher score
        ntile(5) over (order by frequency asc)      as f_score,
        -- M: higher spend = higher score
        ntile(5) over (order by monetary asc)       as m_score
    from rfm_base
)

select
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    r_score + f_score + m_score                                                     as rfm_total_score,
    cast(r_score as varchar) || cast(f_score as varchar) || cast(m_score as varchar) as rfm_cell_code

from rfm_scores
