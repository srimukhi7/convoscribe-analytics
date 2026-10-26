-- int_months: one row per calendar month from the first signup to the data cutoff.
-- A "date spine": it guarantees every month appears in monthly metrics,
-- even a month with no activity.

with bounds as (

    select
        cast(date_trunc('month', min(signed_up_at)) as date) as first_month,
        cast(date_trunc('month', cast('{{ var("data_as_of") }}' as timestamp)) as date) as last_month
    from {{ ref('stg_users') }}

),

months as (

    -- generate_series makes a list of month starts; unnest turns the list into rows
    select
        cast(
            unnest(generate_series(
                cast(first_month as timestamp),
                cast(last_month as timestamp),
                interval '1 month'
            )) as date
        ) as month_start
    from bounds

)

select
    month_start,
    -- The last second of the month, used to ask "who was paying at month end?"
    month_start + interval '1 month' - interval '1 second' as month_end_at
from months