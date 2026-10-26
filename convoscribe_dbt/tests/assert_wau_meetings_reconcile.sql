-- Rule: meetings counted in the weekly metric equal meetings in fct_meetings.

with totals as (

    select
        (select sum(meetings) from {{ ref('metrics_weekly_active_users') }}) as in_metric,
        (select count(*) from {{ ref('fct_meetings') }}) as in_fact

)

select *
from totals
where in_metric <> in_fact