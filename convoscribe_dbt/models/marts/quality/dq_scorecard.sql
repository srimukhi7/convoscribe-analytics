-- dq_scorecard: every raw-data problem we planted (or any real one), with row counts.
-- "measured_on" says whether the count comes from the raw table or the cleaned
-- (staged) table. Used in the dashboard's data quality tab.

with issues as (

    select
        'raw_users' as table_name, 'Duplicate rows removed' as issue, 'raw' as measured_on,
        (select count(*) from {{ source('raw', 'raw_users') }})
            - (select count(*) from {{ ref('stg_users') }}) as rows_affected,
        (select count(*) from {{ source('raw', 'raw_users') }}) as total_rows

    union all

    select
        'raw_users', 'Missing emails', 'staged',
        (select count(*) from {{ ref('stg_users') }} where email is null),
        (select count(*) from {{ ref('stg_users') }})

    union all

    select
        'raw_meetings', 'Duplicate rows removed', 'raw',
        (select count(*) from {{ source('raw', 'raw_meetings') }})
            - (select count(*) from {{ ref('stg_meetings') }}),
        (select count(*) from {{ source('raw', 'raw_meetings') }})

    union all

    select
        'raw_meetings', 'Zero or negative duration (excluded from marts)', 'staged',
        (select count(*) from {{ ref('stg_meetings') }} where not is_valid_duration),
        (select count(*) from {{ ref('stg_meetings') }})

    union all

    select
        'raw_meetings', 'Unknown user_id (excluded from marts)', 'staged',
        (
            select count(*)
            from {{ ref('stg_meetings') }} as m
            left join {{ ref('stg_users') }} as u on u.user_id = m.user_id
            where u.user_id is null
        ),
        (select count(*) from {{ ref('stg_meetings') }})

    union all

    select
        'raw_meetings', 'Arrived more than 1 hour late', 'staged',
        (select count(*) from {{ ref('stg_meetings') }} where is_late_arriving),
        (select count(*) from {{ ref('stg_meetings') }})

    union all

    select
        'raw_feature_events', 'Duplicate rows removed', 'raw',
        (select count(*) from {{ source('raw', 'raw_feature_events') }})
            - (select count(*) from {{ ref('stg_feature_events') }}),
        (select count(*) from {{ source('raw', 'raw_feature_events') }})

    union all

    select
        'raw_feature_events', 'Non-standard event name (standardized)', 'raw',
        (
            select count(*)
            from {{ source('raw', 'raw_feature_events') }}
            where event_name not in
                ('summary_viewed', 'action_item_created', 'transcript_shared', 'ai_chat_used')
        ),
        (select count(*) from {{ source('raw', 'raw_feature_events') }})

    union all

    select
        'raw_feature_events', 'Arrived more than 1 hour late', 'staged',
        (select count(*) from {{ ref('stg_feature_events') }} where is_late_arriving),
        (select count(*) from {{ ref('stg_feature_events') }})

    union all

    select
        'raw_subscription_events', 'Duplicate rows removed', 'raw',
        (select count(*) from {{ source('raw', 'raw_subscription_events') }})
            - (select count(*) from {{ ref('stg_subscription_events') }}),
        (select count(*) from {{ source('raw', 'raw_subscription_events') }})

    union all

    select
        'raw_subscription_events', 'Arrived more than 1 hour late', 'staged',
        (select count(*) from {{ ref('stg_subscription_events') }} where is_late_arriving),
        (select count(*) from {{ ref('stg_subscription_events') }})

)

select
    table_name || ': ' || issue as check_name,
    table_name,
    issue,
    measured_on,
    rows_affected,
    total_rows,
    round(100.0 * rows_affected / nullif(total_rows, 0), 2) as pct_affected
from issues