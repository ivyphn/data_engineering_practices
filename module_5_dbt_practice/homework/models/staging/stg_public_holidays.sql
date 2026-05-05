with source as (
    select * from {{ ref('brazil_public_holidays') }}
)

select
    date(holiday_date)  as holiday_date,
    holiday_name,
    holiday_type
from source
