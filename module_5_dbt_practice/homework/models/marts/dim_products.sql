with products as (
    select * from {{ ref('int_products_enriched') }}
)

select
    -- surrogate key
    product_id                  as product_key,

    -- category
    product_category_name       as category_name_pt,
    category_name_en,

    -- physical attributes
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm,

    -- listing quality
    product_photos_qty

from products
