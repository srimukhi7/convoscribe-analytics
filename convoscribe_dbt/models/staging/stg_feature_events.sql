-- stg_feature_events: one row per AI feature use, with standardized names.

with source as (

    select * from {{ source('raw', 'raw_feature_events') }}

),

deduplicated as (

    select
        *,
        row_number() over (partition by event_id order by ingested_at desc) as row_num
    from source

),

cleaned as (

    select
        event_id,
        user_id,
        -- Summary_Viewed, SUMMARY_VIEWED and "summary viewed" all become summary_viewed
        lower(replace(trim(event_name), ' ', '_')) as event_name,
        cast(event_ts as timestamp) as occurred_at,
        meeting_id,
        cast(ingested_at as timestamp) as ingested_at,
        cast(ingested_at as timestamp)
            > cast(event_ts as timestamp) + interval '1 hour' as is_late_arriving

    from deduplicated
    where row_num = 1

)

select * from cleaned