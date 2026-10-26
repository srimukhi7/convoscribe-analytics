-- stg_users: one clean row per user.

with source as (

    select * from {{ source('raw', 'raw_users') }}

),

deduplicated as (

    -- Raw has exact duplicate rows. Number the copies of each user_id
    -- and keep only copy number 1 (next CTE).
    select
        *,
        row_number() over (partition by user_id order by signup_ts) as row_num
    from source

),

cleaned as (

    select
        user_id,
        -- trim stray spaces, lowercase, and turn empty text into a real NULL
        nullif(lower(trim(email)), '') as email,
        cast(signup_ts as timestamp) as signed_up_at,
        upper(country) as country_code,
        signup_source,
        device as signup_device,
        workspace_id

    from deduplicated
    where row_num = 1

)

select * from cleaned