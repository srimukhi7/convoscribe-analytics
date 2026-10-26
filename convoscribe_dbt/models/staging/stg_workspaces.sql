-- stg_workspaces: one clean row per workspace.

with source as (

    select * from {{ source('raw', 'raw_workspaces') }}

),

cleaned as (

    select
        workspace_id,
        trim(workspace_name) as workspace_name,
        cast(created_ts as timestamp) as created_at,
        plan_at_creation

    from source

)

select * from cleaned