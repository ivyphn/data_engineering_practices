--Review score is valid
SELECT * 
FROM "olist_db"."order_reviews" 
where 
review_score is null 
or review_score not in (1,2,3,4,5)