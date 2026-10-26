-- metrics_conversion
-- Grain: one row per signup month.
-- Definition: free-to-paid conversion = users who started a paid plan within the
-- conversion window (default 30 days) of signing up / MATURE signups.
-- A user who pays at the moment of signup counts as converted.

with users as (

    select
        signup_month,
        has_ever_paid,
        -- has this user had the full window to convert yet?
        signed_up_at + interval '{{ var("conversion_window_days") }} days'
            <= cast('{{ var("data_as_of") }}' as timestamp) as is_mature,
        -- did they start paying inside the window? (NULL first_paid_at becomes false)
        coalesce(
            first_paid_at <= signed_up_at + interval '{{ var("conversion_window_days") }} days',
            false
        ) as converted_in_window
    from {{ ref('dim_users') }}

)

select
    signup_month,
    {{ var("conversion_window_days") }} as conversion_window_days,
    count(*) as signups,
    count(*) filter (where is_mature) as mature_signups,
    count(*) filter (where is_mature and converted_in_window) as converted_within_window,
    round(
        cast(count(*) filter (where is_mature and converted_in_window) as double)
        / nullif(count(*) filter (where is_mature), 0),
        4
    ) as conversion_rate,
    -- Not maturity-adjusted: everyone who has ever paid. Useful context only.
    count(*) filter (where has_ever_paid) as converted_to_date

from users
group by signup_month