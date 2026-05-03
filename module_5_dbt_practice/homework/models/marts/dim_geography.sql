with state_regions as (
    select * from {{ ref('brazil_state_regions') }}
)

select
    state_code,
    state_name,
    macro_region,
    'Brazil'    as country,
    'BR'        as country_code

from state_regions
