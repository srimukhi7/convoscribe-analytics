-- stg_experiment_assignments: which variant each user saw in each experiment.

with source as (

    select * from {{ source('raw', 'raw_experiment_assignments') }}

),

deduplicated as (

    -- A user should be in an experiment only once. Keep the first assignment.
    select
        *,
        row_number() over (
            partition by user_id, experiment_name order by assigned_ts
        ) as row_num
    from source

),

cleaned as (

    select
        user_id,
        experiment_name,
        variant,
        cast(assigned_ts as timestamp) as assigned_at

    from deduplicated
    where row_num = 1

)

select * from cleaned