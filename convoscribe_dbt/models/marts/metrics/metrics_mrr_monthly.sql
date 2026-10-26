-- metrics_mrr_monthly
-- Grain: one row per month.
-- MRR is measured at month end. Movement categories compare each user's MRR at
-- the end of this month with the end of the previous month:
--   new          paid now, not last month (a reactivation counts as new)
--   expansion    paying more than last month
--   contraction  paying less than last month but still paying
--   churned      paid last month, nothing now
-- The bridge always balances:
--   starting + new + expansion - contraction - churned = ending

with user_months as (

    select user_id, month_start, mrr
    from {{ ref('int_user_monthly_mrr') }}

),

movements as (

    -- Pair each user's MRR this month (c) with their MRR last month (p).
    -- FULL OUTER JOIN keeps users who appear in only one of the two months:
    -- a new customer has no last month, a churned customer has no this month.
    select
        coalesce(c.user_id, p.user_id) as user_id,
        coalesce(c.month_start, cast(p.month_start + interval '1 month' as date)) as month_start,
        coalesce(p.mrr, 0) as prev_mrr,
        coalesce(c.mrr, 0) as curr_mrr
    from user_months as c
    full outer join user_months as p
        on  p.user_id = c.user_id
        and cast(p.month_start + interval '1 month' as date) = c.month_start

),

monthly as (

    select
        month_start,
        sum(prev_mrr) as starting_mrr,
        sum(curr_mrr) as ending_mrr,
        sum(case when prev_mrr = 0 and curr_mrr > 0 then curr_mrr else 0 end) as new_mrr,
        sum(case when prev_mrr > 0 and curr_mrr > prev_mrr
                 then curr_mrr - prev_mrr else 0 end) as expansion_mrr,
        sum(case when prev_mrr > 0 and curr_mrr > 0 and curr_mrr < prev_mrr
                 then prev_mrr - curr_mrr else 0 end) as contraction_mrr,
        sum(case when prev_mrr > 0 and curr_mrr = 0 then prev_mrr else 0 end) as churned_mrr,
        count(*) filter (where prev_mrr > 0) as starting_customers,
        count(*) filter (where curr_mrr > 0) as paying_customers,
        count(*) filter (where prev_mrr = 0 and curr_mrr > 0) as new_customers,
        count(*) filter (where prev_mrr > 0 and curr_mrr = 0) as churned_customers
    from movements
    group by month_start

),

filled as (

    -- Start from the month spine so every month appears, with zeros if empty.
    -- This also drops the extra month the full outer join creates after the last month.
    select
        m.month_start,
        coalesce(x.starting_mrr, 0) as starting_mrr,
        coalesce(x.new_mrr, 0) as new_mrr,
        coalesce(x.expansion_mrr, 0) as expansion_mrr,
        coalesce(x.contraction_mrr, 0) as contraction_mrr,
        coalesce(x.churned_mrr, 0) as churned_mrr,
        coalesce(x.ending_mrr, 0) as ending_mrr,
        coalesce(x.starting_customers, 0) as starting_customers,
        coalesce(x.new_customers, 0) as new_customers,
        coalesce(x.churned_customers, 0) as churned_customers,
        coalesce(x.paying_customers, 0) as paying_customers
    from {{ ref('int_months') }} as m
    left join monthly as x on x.month_start = m.month_start

)

select
    month_start,
    starting_mrr,
    new_mrr,
    expansion_mrr,
    contraction_mrr,
    churned_mrr,
    new_mrr + expansion_mrr - contraction_mrr - churned_mrr as net_new_mrr,
    ending_mrr,
    starting_customers,
    new_customers,
    churned_customers,
    paying_customers,

    -- Logo churn: share of last month's customers who left
    round(cast(churned_customers as double) / nullif(starting_customers, 0), 4)
        as logo_churn_rate,

    -- NRR: revenue now from last month's customers / their revenue then.
    -- New customers are excluded because they are not in starting_mrr.
    round(
        cast(starting_mrr + expansion_mrr - contraction_mrr - churned_mrr as double)
        / nullif(starting_mrr, 0),
        4
    ) as net_revenue_retention

from filled