WITH
  dates AS (
   SELECT date_add('day', d, DATE '2016-01-01') date
   FROM
     UNNEST(sequence(0, 4017)) days (d)
   WHERE (date_add('day', d, DATE '2016-01-01') <= DATE '2030-12-31')
) 
, calendar AS (
   SELECT
     date
   , YEAR(date) yr
   , MONTH(date) mth
   , QUARTER(date) qtr
   , day_of_week(date) dow
   FROM
     dates
) 
, holidays AS (
   SELECT
     date
   , holiday_name
   , array_join(array_agg(DISTINCT jurisdiction), ', ') jurisdictions
   FROM
     australian_public_holidays
   GROUP BY date, holiday_name
) 
SELECT
  CAST(date_format(c.date, '%Y%m%d') AS INT) date_key
, CAST(c.date AS DATE) calendar_date
, yr calendar_year
, qtr calendar_quarter
, mth calendar_month_num
, date_format(c.date, '%M') calendar_month_name
, date_format(c.date, '%b') calendar_month_short
, date_format(c.date, '%Y-%m') calendar_year_month
, WEEK(c.date) calendar_week_num
, day_of_year(c.date) day_of_year
, DAY(c.date) day_of_month
, dow day_of_week_num
, date_format(c.date, '%W') day_of_week_name
, (CASE WHEN (dow IN (6, 7)) THEN 1 ELSE 0 END) is_weekend
, (NOT (dow IN (6, 7))) is_weekday
, (c.date = last_day_of_month(c.date)) is_last_day_of_month
, (c.date = (CASE WHEN (qtr = 1) THEN DATE(concat(CAST(yr AS VARCHAR), '-03-31')) WHEN (qtr = 2) THEN DATE(concat(CAST(yr AS VARCHAR), '-06-30')) WHEN (qtr = 3) THEN DATE(concat(CAST(yr AS VARCHAR), '-09-30')) WHEN (qtr = 4) THEN DATE(concat(CAST(yr AS VARCHAR), '-12-31')) END)) is_last_day_of_quarter
, (NOT (dow IN (6, 7))) is_business_day
, (CASE WHEN (mth >= 7) THEN (yr + 1) ELSE yr END) fiscal_year
, concat('FY', SUBSTR(CAST((CASE WHEN (mth >= 7) THEN (yr + 1) ELSE yr END) AS VARCHAR), 3, 2)) fiscal_year_name
, (CASE WHEN (mth IN (7, 8, 9)) THEN 1 WHEN (mth IN (10, 11, 12)) THEN 2 WHEN (mth IN (1, 2, 3)) THEN 3 WHEN (mth IN (4, 5, 6)) THEN 4 END) fiscal_quarter
, (CASE WHEN (mth >= 7) THEN (mth - 6) ELSE (mth + 6) END) fiscal_month_num
, (FLOOR((date_diff('day', (CASE WHEN (mth >= 7) THEN DATE(concat(CAST(yr AS VARCHAR), '-07-01')) ELSE DATE(concat(CAST((yr - 1) AS VARCHAR), '-07-01')) END), c.date) / 7)) + 1) fiscal_week_num
, concat(concat(concat('FY', SUBSTR(CAST((CASE WHEN (mth >= 7) THEN (yr + 1) ELSE yr END) AS VARCHAR), 3, 2)), '-Q'), CAST((CASE WHEN (mth IN (7, 8, 9)) THEN 1 WHEN (mth IN (10, 11, 12)) THEN 2 WHEN (mth IN (1, 2, 3)) THEN 3 WHEN (mth IN (4, 5, 6)) THEN 4 END) AS VARCHAR)) fiscal_period
, (CASE WHEN (h.date IS NOT NULL) THEN 1 ELSE 0 END) is_public_holiday
, h.holiday_name
, h.jurisdictions
FROM
  (calendar c
LEFT JOIN holidays h ON (CAST(date_format(c.date, '%Y%m%d') AS VARCHAR) = h.date))
ORDER BY c.date ASC
