-- fct_daily_activity: daily usage per user.
-- Grain: one row per user per day on which the user had a meeting OR used an AI feature.
-- had_meeting separates "real usage" days from feature-only days.

with meeting_days as (

    select
        user_id,
        meeting_date as activity_date,
        count(*) as meetings,
        sum(duration_minutes) as meeting_minutes
    from {{ ref('fct_meetings') }}
    group by user_id, meeting_date

),

feature_days as (

    select
        e.user_id,
        cast(e.occurred_at as date) as activity_date,
        count(*) filter (where e.event_name = 'summary_viewed')      as summaries_viewed,
        count(*) filter (where e.event_name = 'action_item_created') as action_items_created,
        count(*) filter (where e.event_name = 'transcript_shared')   as transcripts_shared,
        count(*) filter (where e.event_name = 'ai_chat_used')        as ai_chat_questions,
        count(*) as feature_events
    from {{ ref('stg_feature_events') }} as e
    -- Keep only events from known users
    inner join {{ ref('stg_users') }} as u on u.user_id = e.user_id
    group by e.user_id, cast(e.occurred_at as date)

),

combined as (

    -- Full outer join: a day can have meetings, feature use, or both
    select
        coalesce(m.user_id, f.user_id) as user_id,
        coalesce(m.activity_date, f.activity_date) as activity_date,
        coalesce(m.meetings, 0) as meetings,
        coalesce(m.meeting_minutes, 0) as meeting_minutes,
        coalesce(f.summaries_viewed, 0) as summaries_viewed,
        coalesce(f.action_items_created, 0) as action_items_created,
        coalesce(f.transcripts_shared, 0) as transcripts_shared,
        coalesce(f.ai_chat_questions, 0) as ai_chat_questions,
        coalesce(f.feature_events, 0) as feature_events
    from meeting_days as m
    full outer join feature_days as f
        on  m.user_id = f.user_id
        and m.activity_date = f.activity_date

)

select
    *,
    meetings > 0 as had_meeting
from combined