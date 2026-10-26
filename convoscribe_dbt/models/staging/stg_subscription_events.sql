-- stg_subscription_events: one row per paid-plan change.

with source as (

    select * from {{ source('raw', 'raw_subscription_events') }}

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by subscription_event_id order by ingested_at desc
        ) as row_num
    from source

),

cleaned as (

    select
        subscription_event_id,
        user_id,
        event_type,
        plan,
        cast(monthly_price as decimal(10, 2)) as monthly_price,
        cast(event_ts as timestamp) as occurred_at,
        cast(ingested_at as timestamp) as ingested_at,
        cast(ingested_at as timestamp)
            > cast(event_ts as timestamp) + interval '1 hour' as is_late_arriving

    from deduplicated
    where row_num = 1

)

select * from cleaned