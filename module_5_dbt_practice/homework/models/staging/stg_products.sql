with source as (
    select * from {{ ref('olist_products') }}
)

select
    product_id,
    product_category_name,
    -- source has a known typo: 'lenght' instead of 'length'
    cast(product_name_lenght as int)            as product_name_length,
    cast(product_description_lenght as int)     as product_description_length,
    cast(product_photos_qty as int)             as product_photos_qty,
    cast(product_weight_g as decimal(10, 2))    as product_weight_g,
    cast(product_length_cm as decimal(10, 2))   as product_length_cm,
    cast(product_height_cm as decimal(10, 2))   as product_height_cm,
    cast(product_width_cm as decimal(10, 2))    as product_width_cm

from source
