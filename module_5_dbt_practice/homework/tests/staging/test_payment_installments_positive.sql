-- Installment count must be at least 1. Zero installments is not a valid payment plan.
select
    order_id,
    payment_sequential,
    payment_installments
from {{ ref('stg_order_payments') }}
where payment_installments < 1
