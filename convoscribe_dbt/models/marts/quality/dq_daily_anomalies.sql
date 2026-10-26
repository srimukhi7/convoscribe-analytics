-- dq_daily_anomalies: flags days where a key metric is unusual.
-- Grain: one row per day per metric (meetings, active_users, signups).
--
-- Method:
--   baseline = average of the previous 8 SAME WEEKDAYS (so weekends are compared
--              with weekends, not with weekdays)
--   z_score  = (value - baseline) / standard deviation of those 8 days
--   anomaly  = z_score and the % change are both large (thresholds are project vars)
-- A day is only evaluated if there are at least 4 baseline days and the baseline is
-- above a per-metric minimum, so tiny early-days numbers do not trigger alerts.

with bounds as (

    select
        cast(min(signed_up_at) as date) as first_day,
        cast(cast('{{ var("data_as_of") }}' as timestamp) as date) as last_day
    from {{ ref('stg_users') }}

),

days as (

    -- Date spine: one row per calendar day, so quiet days show up as zeros
    select
        cast(unnest(generate_series(
            cast(first_day as timestamp),
            cast(last_day as timestamp),
            interval '1 day'
        )) as date) as activity_date
    from bounds

),

meetings_daily as (

    select
        meeting_date as activity_date,
        count(*) as meetings,
        count(distinct user_id) as active_users
    from {{ ref('fct_meetings') }}
    group by 1

),

signups_daily as (

    select signup_date as activity_date, count(*) as signups
    from {{ ref('dim_users') }}
    group by 1

),

daily as (

    select
        d.activity_date,
        coalesce(m.meetings, 0) as meetings,
        coalesce(m.active_users, 0) as active_users,
        coalesce(s.signups, 0) as signups
    from days as d
    left join meetings_daily as m on m.activity_date = d.activity_date
    left join signups_daily as s on s.activity_date = d.activity_date

),

long_format as (

    -- Stack the three metrics into rows so one set of logic scores them all
    select activity_date, 'meetings' as metric_name, meetings as metric_value from daily
    union all
    select activity_date, 'active_users', active_users from daily
    union all
    select activity_date, 'signups', signups from daily

),

metric_config as (

    -- Minimum baseline per metric: below this the numbers are too small to judge
    select * from (
        values ('meetings', 50), ('active_users', 30), ('signups', 10)
    ) as t(metric_name, min_baseline)

),

baselined as (

    select
        activity_date,
        metric_name,
        metric_value,
        avg(metric_value) over w as baseline_mean,
        stddev_samp(metric_value) over w as baseline_stddev,
        count(metric_value) over w as baseline_points
    from long_format
    -- Named window: for each metric and weekday, look at the previous 8 matching days
    window w as (
        partition by metric_name, dayofweek(activity_date)
        order by activity_date
        rows between 8 preceding and 1 preceding
    )

),

scored as (

    select
        b.*,
        c.min_baseline,
        (b.metric_value - b.baseline_mean) / nullif(b.baseline_stddev, 0) as z_score,
        (b.metric_value - b.baseline_mean) / nullif(b.baseline_mean, 0) as pct_change_vs_baseline
    from baselined as b
    inner join metric_config as c on c.metric_name = b.metric_name

),

evaluated as (

    select
        *,
        coalesce(baseline_points >= 4 and baseline_mean >= min_baseline, false) as is_evaluated
    from scored

),

flagged as (

    select
        *,
        coalesce(
            is_evaluated
            and abs(z_score) > {{ var("anomaly_z_threshold") }}
            and abs(pct_change_vs_baseline) > {{ var("anomaly_min_pct_change") }},
            false
        ) as is_anomaly
    from evaluated

)

select
    metric_name || '|' || cast(activity_date as varchar) as anomaly_key,
    activity_date,
    metric_name,
    metric_value,
    round(baseline_mean, 1) as baseline_mean,
    round(baseline_stddev, 1) as baseline_stddev,
    baseline_points,
    round(z_score, 2) as z_score,
    round(pct_change_vs_baseline, 3) as pct_change_vs_baseline,
    is_evaluated,
    is_anomaly,
    case
        when is_anomaly and z_score < 0 then 'drop'
        when is_anomaly then 'spike'
    end as direction
from flagged