-- Retention rate is a proportion and must be between 0 and 1 inclusive.
select
    acquisition_month,
    activity_month,
    retention_rate
from {{ ref('fct_customer_cohorts') }}
where retention_rate < 0
   or retention_rate > 1
