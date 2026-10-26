-- metrics_cohort_retention
-- Grain: one row per signup-month cohort per month-since-signup.
-- Definition: retention in month N = share of the cohort that had at least one
-- valid meeting in calendar month N after their signup month (month 0 = signup month).
-- Month 0 is below 100% because some users never record a meeting.
-- Only months that have fully elapsed before the data cutoff are shown.

with cohorts as (

    select signup_month as cohort_month, count(*) as cohort_size
    from {{ ref('dim_users') }}
    group by 1

),

bounds as (

    select cast(date_trunc('month', cast('{{ var("data_as_of") }}' as timestamp)) as date) as last_month

),

offsets as (

    select unnest(generate_series(0, 12)) as months_since_signup

),

grid as (

    -- Every cohort paired with every month offset that has already happened
    select
        c.cohort_month,
        c.cohort_size,
        o.months_since_signup
    from cohorts as c
    cross join offsets as o
    cross join bounds as b
    where cast(c.cohort_month + to_months(o.months_since_signup) as date) <= b.last_month

),

retained as (

    -- Distinct users with a meeting, by cohort and months since signup
    select
        u.signup_month as cohort_month,
        date_diff('month', u.signup_month, cast(date_trunc('month', m.meeting_date) as date))
            as months_since_signup,
        count(distinct m.user_id) as retained_users
    from {{ ref('fct_meetings') }} as m
    inner join {{ ref('dim_users') }} as u on u.user_id = m.user_id
    group by 1, 2

)

select
    g.cohort_month,
    g.months_since_signup,
    g.cohort_size,
    coalesce(r.retained_users, 0) as retained_users,
    round(cast(coalesce(r.retained_users, 0) as double) / g.cohort_size, 4) as retention_rate

from grid as g
left join retained as r
    on  r.cohort_month = g.cohort_month
    and r.months_since_signup = g.months_since_signup