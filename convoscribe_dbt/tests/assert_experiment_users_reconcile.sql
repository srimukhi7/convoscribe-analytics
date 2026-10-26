-- Rule: every assigned user is counted exactly once across the variants.
-- Returns a row only if the totals disagree.
with totals as (
    select
        (select sum(assigned_users) from {{ ref('exp_variant_results') }}) as in_results,
        (select count(*) from {{ ref('stg_experiment_assignments') }}) as staged
)
select *
from totals
where in_results <> staged