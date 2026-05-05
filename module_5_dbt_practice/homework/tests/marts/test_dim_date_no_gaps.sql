-- The date spine must have no gaps — every consecutive pair of dates must be exactly 1 day apart.
with ordered as (
    select
        calendar_date,
        lead(calendar_date) over (order by calendar_date) as next_date
    from {{ ref('dim_date') }}
)

select
    calendar_date,
    next_date
from ordered
where next_date is not null
  and date_diff('day', calendar_date, next_date) > 1
