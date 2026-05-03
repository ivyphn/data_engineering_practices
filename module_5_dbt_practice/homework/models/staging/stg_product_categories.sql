with source as (
    select * from {{ ref('olist_product_category_name_translation') }}
)

select
    product_category_name           as category_name_pt,
    product_category_name_english   as category_name_en

from source
