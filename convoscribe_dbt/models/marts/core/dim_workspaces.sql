-- dim_workspaces: the source of truth for team workspaces.
-- Grain: one row per workspace (570 rows).

with workspaces as (

    select * from {{ ref('stg_workspaces') }}

),

members as (

    -- Roll the user table up to workspace level
    select
        workspace_id,
        count(*) as member_count,
        count(*) filter (where is_currently_paid) as paying_member_count,
        count(*) filter (where is_activated) as activated_member_count,
        sum(lifetime_meetings) as lifetime_meetings
    from {{ ref('dim_users') }}
    where workspace_id is not null
    group by workspace_id

)

select
    w.workspace_id,
    w.workspace_name,
    w.created_at,
    w.plan_at_creation,
    coalesce(m.member_count, 0) as member_count,
    coalesce(m.paying_member_count, 0) as paying_member_count,
    coalesce(m.activated_member_count, 0) as activated_member_count,
    coalesce(m.lifetime_meetings, 0) as lifetime_meetings

from workspaces as w
left join members as m on m.workspace_id = w.workspace_id