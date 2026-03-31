SELECT 
    customer_unique_id as id, 
    customer_id as customer_string,
    customer_zip_code_prefix as postcode, 
    customer_city as city, 
    customer_state as state
FROM {{ source('ol', 'customers') }};