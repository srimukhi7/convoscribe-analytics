-- Rule: each month's starting MRR equals the previous month's ending MRR.

with ordered as (

    select
        month_start,
        starting_mrr,
        lag(ending_mrr) over (order by month_start) as previous_ending_mrr
    from {{ ref('metrics_mrr_monthly') }}

)

select *
from ordered
where previous_ending_mrr is not null
  and starting_mrr <> previous_ending_mrr