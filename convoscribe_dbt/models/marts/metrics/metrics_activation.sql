-- metrics_activation
-- Grain: one row per signup week.
-- Definition: activation rate = activated users / MATURE signups
-- (users who have had the full activation window). Immature users are counted
-- in "signups" but excluded from the rate, so recent weeks are not understated.

select
    cast(date_trunc('week', signed_up_at) as date) as signup_week,
    count(*) as signups,
    count(*) filter (where is_activation_window_complete) as mature_signups,
    count(*) filter (where is_activation_window_complete and is_activated) as activated_users,

    -- nullif turns a zero denominator into NULL, so the rate is blank, not an error
    round(
        cast(count(*) filter (where is_activation_window_complete and is_activated) as double)
        / nullif(count(*) filter (where is_activation_window_complete), 0),
        4
    ) as activation_rate

from {{ ref('dim_users') }}
group by 1