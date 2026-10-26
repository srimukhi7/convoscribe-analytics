-- Rule: starting + new + expansion - contraction - churned = ending, every month.

select
    month_start, starting_mrr, new_mrr, expansion_mrr,
    contraction_mrr, churned_mrr, ending_mrr
from {{ ref('metrics_mrr_monthly') }}
where ending_mrr <> starting_mrr + new_mrr + expansion_mrr - contraction_mrr - churned_mrr