-- fct_subscriptions: the source of truth for paid subscription periods.
-- Grain: one row per paid period (594 rows).
-- Active periods have no end date, so we add period_end_or_cutoff_at, which
-- uses the data cutoff date instead. That makes durations easy to calculate.

with periods as (

    select
        *,
        coalesce(period_end_at, cast('{{ var("data_as_of") }}' as timestamp))
            as period_end_or_cutoff_at
    from {{ ref('int_subscription_periods') }}

)

select
    subscription_period_id,
    user_id,
    plan,
    monthly_price,
    period_start_at,
    period_end_at,
    period_end_or_cutoff_at,
    started_by_event,
    ended_by_event,
    is_active_period,
    date_diff(
        'day',
        cast(period_start_at as date),
        cast(period_end_or_cutoff_at as date)
    ) as period_days

from periods