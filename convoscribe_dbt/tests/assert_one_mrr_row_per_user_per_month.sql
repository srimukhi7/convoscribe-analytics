-- Rule: a user has at most one MRR row per month (periods never overlap).

select user_id, month_start, count(*) as row_count
from {{ ref('int_user_monthly_mrr') }}
group by user_id, month_start
having count(*) > 1