with date_spine as (
    -- Generate one row per calendar day for the full data range (2016–2025)
    -- Cast to DATE explicitly: Athena sequence() returns timestamp(0) by default
    -- which causes a precision mismatch when writing to a TABLE materialisation
    select cast(calendar_date as date) as calendar_date
    from (
        values (sequence(date('2016-01-01'), date('2025-12-31'), interval '1' day))
    ) as t(dates)
    cross join unnest(dates) as t2(calendar_date)
),

holidays as (
    -- All entries in stg_public_holidays are Brazilian national holidays
    select
        holiday_date,
        holiday_name,
        holiday_type
    from {{ ref('stg_public_holidays') }}
)

select
    -- integer surrogate key in YYYYMMDD format
    cast(date_format(d.calendar_date, '%Y%m%d') as int)     as date_key,
    d.calendar_date,

    -- calendar breakdowns
    {{ date_part('year',    'd.calendar_date') }}            as year,
    {{ date_part('quarter', 'd.calendar_date') }}            as quarter,
    {{ date_part('month',   'd.calendar_date') }}            as month,
    {{ date_part('day',     'd.calendar_date') }}            as day,

    -- week attributes
    {{ date_part('dow',     'd.calendar_date') }}            as day_of_week_num,
    -- 1=Mon … 7=Sun in Presto; flag weekend
    case
        when {{ date_part('dow', 'd.calendar_date') }} in (6, 7) then true
        else false
    end                                                      as is_weekend,

    -- business day flag
    case
        when {{ date_part('dow', 'd.calendar_date') }} in (6, 7)
             or h.holiday_date is not null
        then false else true
    end                                                      as is_business_day,

    -- Brazilian public holiday flag
    case
        when h.holiday_date is not null then true
        else false
    end                                                      as is_public_holiday,
    h.holiday_name,
    h.holiday_type

from date_spine as d
left join holidays as h
    on d.calendar_date = h.holiday_date
