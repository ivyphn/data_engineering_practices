with sellers as (
    select * from {{ ref('stg_sellers') }}
),

geography as (
    select state_code, macro_region
    from {{ ref('dim_geography') }}
)

select
    -- surrogate key
    s.seller_id                 as seller_key,

    -- descriptive attributes
    s.seller_city,
    s.seller_state,
    g.macro_region              as seller_macro_region,
    s.seller_zip_code_prefix

from sellers as s
left join geography as g
    on s.seller_state = g.state_code
