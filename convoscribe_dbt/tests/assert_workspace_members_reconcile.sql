-- Rule: member counts across workspaces add up to the users who belong to a workspace.

with totals as (

    select
        (select sum(member_count) from {{ ref('dim_workspaces') }}) as workspace_total,
        (select count(*) from {{ ref('dim_users') }} where workspace_id is not null) as user_total

)

select *
from totals
where workspace_total <> user_total