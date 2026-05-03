with order_payments as (
    select * from {{ ref('stg_order_payments') }}
),

-- Total payment value, instalment count, and payment method diversity per order
payments_agg as (
    select
        order_id,
        sum(payment_value)                  as total_payment_value,
        max(payment_installments)           as max_installments,
        count(distinct payment_type)        as payment_method_count
    from order_payments
    group by order_id
),

-- Identify the primary payment type as the one with the highest payment value
primary_payment as (
    select
        order_id,
        payment_type as primary_payment_type
    from (
        select
            order_id,
            payment_type,
            row_number() over (
                partition by order_id
                order by payment_value desc, payment_sequential asc
            ) as rn
        from order_payments
    )
    where rn = 1
)

select
    a.order_id,
    a.total_payment_value,
    a.max_installments,
    a.payment_method_count,
    case when a.payment_method_count > 1 then true else false end as payment_split_flag,
    p.primary_payment_type

from payments_agg as a
left join primary_payment as p
    on a.order_id = p.order_id
