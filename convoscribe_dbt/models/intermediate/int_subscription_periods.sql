-- int_subscription_periods: one row per PAID period of a user's subscription.
--
-- Staging holds EVENTS (started, upgraded, downgraded, cancelled, reactivated).
-- Here we convert them into PERIODS with a start and an end:
--   started / upgraded / downgraded / reactivated  -> a new period BEGINS
--   the user's next event of any kind              -> the period ENDS
-- A cancelled event begins nothing (the user is back on the free plan).
-- A period with no end date is still active at the data cutoff.

with events as (

    select
        subscription_event_id,
        user_id,
        event_type,
        plan,
        monthly_price,
        occurred_at,

        -- Look ahead to the same user's next event (ordered by time;
        -- the id breaks ties so ordering is always deterministic)
        lead(occurred_at) over (
            partition by user_id order by occurred_at, subscription_event_id
        ) as next_event_at,

        lead(event_type) over (
            partition by user_id order by occurred_at, subscription_event_id
        ) as next_event_type

    from {{ ref('stg_subscription_events') }}

),

periods as (

    select
        user_id,
        plan,
        monthly_price,
        occurred_at as period_start_at,
        next_event_at as period_end_at,       -- null means still active
        event_type as started_by_event,
        next_event_type as ended_by_event

    from events
    -- Keep only events that begin a paid period
    where event_type in ('started', 'upgraded', 'downgraded', 'reactivated')

),

numbered as (

    select
        -- Period 1, 2, 3... per user, in time order
        user_id || '-' || cast(
            row_number() over (partition by user_id order by period_start_at) as varchar
        ) as subscription_period_id,
        *,
        period_end_at is null as is_active_period

    from periods

)

select * from numbered