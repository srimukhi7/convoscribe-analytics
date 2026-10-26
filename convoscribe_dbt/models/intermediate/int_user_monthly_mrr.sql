-- int_user_monthly_mrr: each user's MRR at the end of each month.
-- Grain: one row per user per month in which they had an active paid period at
-- month end. Months where the user was not paying have no row (MRR is zero).
--
-- Known limitation (documented in the metric dictionary): a user who starts and
-- cancels inside the same month is never "active at month end", so they never
-- appear here.

select
    p.user_id,
    m.month_start,
    p.plan,
    p.monthly_price as mrr

from {{ ref('int_months') }} as m
inner join {{ ref('int_subscription_periods') }} as p
    -- the period began on or before month end, and had not yet ended
    on  p.period_start_at <= m.month_end_at
    and (p.period_end_at is null or p.period_end_at > m.month_end_at)