-- exp_variant_results: conversion per experiment variant.
-- Grain: one row per experiment per variant.
-- Primary metric: started a paid plan within N days of assignment (N is the project
-- variable experiment_window_days). Only MATURE users (who have had the full window)
-- are used for rates. The confidence interval is a normal approximation at 95% level.

with experiment_users as (

    select
        a.experiment_name,
        a.variant,
        a.user_id,

        -- Has this user had the full window since being assigned?
        a.assigned_at + interval '{{ var("experiment_window_days") }} days'
            <= cast('{{ var("data_as_of") }}' as timestamp) as is_mature,

        -- Did they start paying inside the window? A user who never paid has a
        -- NULL first_paid_at, so coalesce turns that into false.
        coalesce(
            u.first_paid_at <= a.assigned_at + interval '{{ var("experiment_window_days") }} days',
            false
        ) as converted_in_window

    from {{ ref('stg_experiment_assignments') }} as a
    inner join {{ ref('dim_users') }} as u on u.user_id = a.user_id

),

by_variant as (

    select
        experiment_name,
        variant,
        count(*) as assigned_users,
        count(*) filter (where is_mature) as mature_users,
        count(*) filter (where is_mature and converted_in_window) as converted_users
    from experiment_users
    group by 1, 2

),

rates as (

    select
        *,
        cast(converted_users as double) / nullif(mature_users, 0) as p
    from by_variant

)

select
    experiment_name,
    variant,
    assigned_users,
    mature_users,
    converted_users,
    round(p, 4) as conversion_rate,
    -- 95% confidence interval: rate plus or minus 1.96 standard errors (kept inside 0 to 1)
    round(greatest(p - 1.96 * sqrt(p * (1 - p) / mature_users), 0), 4) as ci_low,
    round(least(p + 1.96 * sqrt(p * (1 - p) / mature_users), 1), 4) as ci_high
from rates