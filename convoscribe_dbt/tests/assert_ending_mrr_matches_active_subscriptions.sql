-- Revenue reconciliation: the last month's ending MRR must equal the total monthly
-- price of every subscription still active at the data cutoff in fct_subscriptions.
-- Two independent calculations of the same number.

with metric as (

    select ending_mrr
    from {{ ref('metrics_mrr_monthly') }}
    order by month_start desc
    limit 1

),

direct as (

    select coalesce(sum(monthly_price), 0) as active_mrr
    from {{ ref('fct_subscriptions') }}
    where is_active_period

)

select metric.ending_mrr, direct.active_mrr
from metric
cross join direct
where metric.ending_mrr <> direct.active_mrr