-- stg_meetings: one row per meeting, with quality flags.
-- Bad rows are FLAGGED, not deleted, so excluding them is a visible decision
-- made later in the marts.

with source as (

    select * from {{ source('raw', 'raw_meetings') }}

),

deduplicated as (

    -- A retried upload creates a second copy with a later ingested_at.
    -- Keep the most recently ingested copy of each meeting_id.
    select
        *,
        row_number() over (partition by meeting_id order by ingested_at desc) as row_num
    from source

),

cleaned as (

    select
        meeting_id,
        user_id,
        cast(started_at as timestamp) as started_at,
        duration_minutes,
        platform,
        participant_count,
        language as language_code,
        cast(ingested_at as timestamp) as ingested_at,

        -- Flag: durations must be greater than zero (tracking plan rule)
        duration_minutes > 0 as is_valid_duration,

        -- Flag: events should arrive within one hour (tracking plan rule)
        cast(ingested_at as timestamp)
            > cast(started_at as timestamp) + interval '1 hour' as is_late_arriving

    from deduplicated
    where row_num = 1

)

select * from cleaned