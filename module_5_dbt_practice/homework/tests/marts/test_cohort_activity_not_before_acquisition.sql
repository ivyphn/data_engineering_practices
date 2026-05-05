-- A cohort cannot have activity before the month it was acquired.
-- months_since_acquisition must always be >= 0.
select
    acquisition_month,
    activity_month,
    months_since_acquisition
from {{ ref('fct_customer_cohorts') }}
where activity_month < acquisition_month
   or months_since_acquisition < 0
