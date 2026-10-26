-- dim_users: the source of truth for users.
-- Grain: one row per user (5,000 rows).
-- Combines profile, activation, usage and subscription status so nobody has to
-- recompute them.

with users as (

    select * from {{ ref('stg_users') }}

),

activation as (

    select
        user_id,
        meetings_in_activation_window,
        first_meeting_at,
        is_activation_window_complete,
        is_activated
    from {{ ref('int_user_activation') }}

),

meeting_totals as (

    -- Valid meetings only. Orphan meetings match no user, so they drop out here.
    select
        user_id,
        count(*) as lifetime_meetings,
        max(started_at) as last_meeting_at
    from {{ ref('stg_meetings') }}
    where is_valid_duration
    group by user_id

),

subscriptions as (

    select
        user_id,
        min(period_start_at) as first_paid_at,
        count(*) as paid_period_count,
        -- Periods never overlap, so at most one is open (still active)
        max(case when is_active_period then plan end) as active_plan
    from {{ ref('int_subscription_periods') }}
    group by user_id

)

select
    u.user_id,
    u.email,
    u.signed_up_at,
    cast(u.signed_up_at as date) as signup_date,
    cast(date_trunc('month', u.signed_up_at) as date) as signup_month,
    u.country_code,
    u.signup_source,
    u.signup_device,
    u.workspace_id,

    -- Activation
    a.is_activated,
    a.is_activation_window_complete,
    a.meetings_in_activation_window,
    a.first_meeting_at,

    -- Usage
    coalesce(m.lifetime_meetings, 0) as lifetime_meetings,
    m.last_meeting_at,

    -- Subscription (users with no paid period are on the free plan)
    s.first_paid_at is not null as has_ever_paid,
    s.first_paid_at,
    coalesce(s.paid_period_count, 0) as paid_period_count,
    coalesce(s.active_plan, 'free') as current_plan,
    s.active_plan is not null as is_currently_paid

from users as u
left join activation as a on a.user_id = u.user_id
left join meeting_totals as m on m.user_id = u.user_id
left join subscriptions as s on s.user_id = u.user_id