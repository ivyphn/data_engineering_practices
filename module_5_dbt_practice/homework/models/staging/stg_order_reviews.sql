with source as (
    select * from {{ ref('olist_order_reviews') }}
)

select
    review_id,
    order_id,
    cast(review_score as int)                               as review_score,
    review_comment_title                                    as comment_title,
    review_comment_message                                  as comment_message,
    {{ convert_timezone('review_creation_date') }}          as review_creation_date,
    {{ convert_timezone('review_answer_timestamp') }}       as review_answer_timestamp
from source
