-- Rule 1: a period must end after it starts.
select
    subscription_period_id,
    'ends_before_it_starts' as problem
from {{ ref('int_subscription_periods') }}
where period_end_at <= period_start_at

union all

-- Rule 2: one user's periods must never overlap (no double-counted revenue).
-- Back-to-back periods (one ends exactly when the next starts) are fine.
select
    a.subscription_period_id,
    'overlaps_another_period' as problem
from {{ ref('int_subscription_periods') }} as a
inner join {{ ref('int_subscription_periods') }} as b
    on  a.user_id = b.user_id
    and a.subscription_period_id < b.subscription_period_id
    and a.period_start_at < coalesce(b.period_end_at, timestamp '2100-01-01')
    and b.period_start_at < coalesce(a.period_end_at, timestamp '2100-01-01')