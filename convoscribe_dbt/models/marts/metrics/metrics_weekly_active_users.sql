-- metrics_weekly_active_users
-- Grain: one row per week (weeks start on Monday).
-- Definition: a user is "active" in a week if they had at least one VALID meeting.
-- Source: fct_meetings, which already excludes invalid and unknown-user meetings.

with weekly as (

    select
        cast(date_trunc('week', meeting_date) as date) as week_start,
        count(distinct user_id) as weekly_active_users,
        count(*) as meetings,
        sum(duration_minutes) as meeting_minutes
    from {{ ref('fct_meetings') }}
    group by 1

),

bounds as (

    select
        cast(min(signed_up_at) as date) as data_start,
        cast(cast('{{ var("data_as_of") }}' as timestamp) as date) as data_end
    from {{ ref('stg_users') }}

)

select
    w.week_start,
    w.weekly_active_users,
    w.meetings,
    w.meeting_minutes,
    round(cast(w.meetings as double) / w.weekly_active_users, 2) as meetings_per_active_user,

    -- A week is complete only if all seven days fall inside our data range.
    -- The first and last weeks are partial and would look like false dips.
    (w.week_start >= b.data_start and w.week_start + 6 <= b.data_end) as is_complete_week

from weekly as w
cross join bounds as b