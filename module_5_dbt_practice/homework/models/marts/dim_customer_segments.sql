with rfm as (
    select * from {{ ref('int_customer_rfm') }}
)

select
    customer_unique_id          as customer_key,

    -- raw RFM metrics
    recency_days,
    frequency,
    monetary,

    -- individual scores (1 = lowest, 5 = highest)
    r_score,
    f_score,
    m_score,
    rfm_total_score,
    rfm_cell_code,

    -- segment label derived from score combinations
    case
        when r_score >= 4 and f_score >= 4 and m_score >= 4
            then 'Champions'
        when r_score >= 4 and f_score >= 2 and m_score >= 3
            then 'Potential Loyalists'
        when r_score >= 4 and f_score <= 1
            then 'New Customers'
        when r_score >= 3 and f_score >= 3 and m_score >= 3
            then 'Loyal Customers'
        when r_score = 3 and f_score <= 3
            then 'Needs Attention'
        when r_score <= 2 and f_score >= 3 and m_score >= 3
            then 'At Risk'
        when r_score <= 2 and f_score >= 4 and m_score >= 4
            then 'Cannot Lose Them'
        when r_score <= 2 and f_score <= 2 and m_score <= 2
            then 'Lost'
        else 'Hibernating'
    end                         as customer_segment,

    -- value tier for easier BI bucketing
    case
        when m_score = 5 then 'Platinum'
        when m_score = 4 then 'Gold'
        when m_score = 3 then 'Silver'
        else 'Bronze'
    end                         as value_tier

from rfm
