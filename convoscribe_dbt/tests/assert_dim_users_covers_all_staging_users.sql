-- Rule: no user is lost between staging and dim_users.
-- Returns any staged user missing from the dimension.

select user_id from {{ ref('stg_users') }}

except

select user_id from {{ ref('dim_users') }}