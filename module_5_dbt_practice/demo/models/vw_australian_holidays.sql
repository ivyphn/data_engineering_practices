select 
    id, 
    date, 
    holiday_name, 
    jurisdiction
from {{ ref('australian_public_holidays') }}