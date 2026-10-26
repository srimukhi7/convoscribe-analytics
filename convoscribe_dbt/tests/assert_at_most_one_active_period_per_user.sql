-- Rule: a user can have at most one open (active) paid period.
-- More than one would double-count revenue.

select user_id, count(*) as active_periods
from {{ ref('fct_subscriptions') }}
where is_active_period
group by user_id
having count(*) > 1