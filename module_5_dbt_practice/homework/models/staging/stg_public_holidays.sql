with source as (
    select * from {{ ref('brazil_public_holidays') }}
)

select
    -- holiday_date is stored as YYYY-MM-DD string in the seed
    date(holiday_date)  as holiday_date,
    holiday_name,
    holiday_type

from source
