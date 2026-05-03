with products as (
    select * from {{ ref('stg_products') }}
),

categories as (
    select * from {{ ref('stg_product_categories') }}
)

select
    p.product_id,
    p.product_category_name,
    -- Fall back to the Portuguese name when no translation exists
    coalesce(c.category_name_en, p.product_category_name) as category_name_en,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    p.product_photos_qty

from products as p
left join categories as c
    on p.product_category_name = c.category_name_pt
