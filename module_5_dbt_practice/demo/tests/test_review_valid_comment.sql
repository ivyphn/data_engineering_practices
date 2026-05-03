--Review comment is not null
SELECT * 
FROM {{ source('ol', 'order_reviews') }}
where review_comment_message is null