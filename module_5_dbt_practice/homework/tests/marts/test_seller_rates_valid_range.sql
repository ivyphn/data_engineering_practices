-- On-time delivery rate and cancellation rate are proportions (0–1).
-- Values outside this range indicate a calculation bug.
select
    seller_key,
    order_month,
    on_time_delivery_rate,
    cancellation_rate
from {{ ref('fct_seller_monthly_metrics') }}
where (on_time_delivery_rate is not null and (on_time_delivery_rate < 0 or on_time_delivery_rate > 1))
   or (cancellation_rate is not null and (cancellation_rate < 0 or cancellation_rate > 1))
