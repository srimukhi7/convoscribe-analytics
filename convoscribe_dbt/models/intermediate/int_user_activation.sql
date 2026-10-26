-- int_user_activation: one row per user showing early engagement.
--
-- "Activated" = at least N valid meetings within D days of signup.
-- N and D come from project variables, so the definition lives in one place.

with users as (

    select user_id, signed_up_at
    from {{ ref('stg_users') }}

),

valid_meetings as (

    -- Only meetings with a valid duration count as real usage
    select meeting_id, user_id, started_at
    from {{ ref('stg_meetings') }}
    where is_valid_duration

),

meetings_in_window as (

    -- Start from USERS and LEFT JOIN meetings so users with zero meetings
    -- still appear (with a count of 0). Orphan meetings (unknown users)
    -- fall away automatically because they match no user.
    select
        u.user_id,
        count(m.meeting_id) as meetings_in_activation_window

    from users as u
    left join valid_meetings as m
        on  m.user_id = u.user_id
        and m.started_at >= u.signed_up_at
        and m.started_at <  u.signed_up_at
                            + interval '{{ var("activation_window_days") }} days'
    group by u.user_id

),

first_meeting as (

    select user_id, min(started_at) as first_meeting_at
    from valid_meetings
    group by user_id

)

select
    u.user_id,
    u.signed_up_at,
    w.meetings_in_activation_window,
    f.first_meeting_at,

    -- Has this user had the full window to activate yet?
    -- Users signing up near the cutoff have not. Rates must exclude them.
    u.signed_up_at + interval '{{ var("activation_window_days") }} days'
        <= cast('{{ var("data_as_of") }}' as timestamp) as is_activation_window_complete,

    w.meetings_in_activation_window >= {{ var("activation_min_meetings") }} as is_activated

from users as u
inner join meetings_in_window as w on w.user_id = u.user_id
left join first_meeting as f on f.user_id = u.user_id