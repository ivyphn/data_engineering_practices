with order_reviews as (
    select * from {{ ref('stg_order_reviews') }}
),

-- Aggregate scores per order
reviews_agg as (
    select
        order_id,
        round(avg(cast(review_score as double)), 2)  as avg_review_score,
        max(review_score)                            as max_review_score,
        count(*)                                     as review_count
    from order_reviews
    group by order_id
),

-- Pick the comment from the most recently created review
latest_review as (
    select
        order_id,
        comment_message as latest_comment
    from (
        select
            order_id,
            comment_message,
            row_number() over (
                partition by order_id
                order by review_creation_date desc
            ) as rn
        from order_reviews
    )
    where rn = 1
)

select
    a.order_id,
    a.avg_review_score,
    a.max_review_score,
    a.review_count,
    r.latest_comment

from reviews_agg as a
left join latest_review as r
    on a.order_id = r.order_id
