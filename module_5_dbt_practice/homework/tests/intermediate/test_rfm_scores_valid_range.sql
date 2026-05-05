-- RFM scores are quintiles and must be between 1 and 5 inclusive.
select
    customer_unique_id,
    r_score,
    f_score,
    m_score
from {{ ref('int_customer_rfm') }}
where r_score not between 1 and 5
   or f_score not between 1 and 5
   or m_score not between 1 and 5
