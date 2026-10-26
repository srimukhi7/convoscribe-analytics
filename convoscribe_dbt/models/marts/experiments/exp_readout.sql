-- exp_readout: the decision table. One row per experiment.
-- Statistics:
--   z_statistic : two-proportion z-test using the pooled conversion rate
--   |z| > 1.96  : significant at the 5% level
--   lift CI     : 95% confidence interval for (treatment - control), unpooled
--   SRM chi2    : checks the split is really ~50/50; above 10.83 means randomisation
--                 is probably broken and the result should not be trusted

with variants as (

    select * from {{ ref('exp_variant_results') }}

),

pivoted as (

    -- Turn two rows (control, treatment) into one row with side-by-side columns
    select
        experiment_name,
        max(assigned_users)  filter (where variant = 'control')   as control_assigned,
        max(assigned_users)  filter (where variant = 'treatment') as treatment_assigned,
        max(mature_users)    filter (where variant = 'control')   as control_n,
        max(mature_users)    filter (where variant = 'treatment') as treatment_n,
        max(converted_users) filter (where variant = 'control')   as control_converted,
        max(converted_users) filter (where variant = 'treatment') as treatment_converted
    from variants
    group by experiment_name

),

rates as (

    select
        *,
        cast(control_converted as double)   / control_n   as control_rate,
        cast(treatment_converted as double) / treatment_n as treatment_rate,
        -- Pooled rate: overall conversion across both groups together
        cast(control_converted + treatment_converted as double)
            / (control_n + treatment_n) as pooled_rate
    from pivoted

),

stats as (

    select
        *,
        treatment_rate - control_rate as absolute_lift,
        (treatment_rate - control_rate) / nullif(control_rate, 0) as relative_lift,

        (treatment_rate - control_rate) / sqrt(
            pooled_rate * (1 - pooled_rate) * (1.0 / control_n + 1.0 / treatment_n)
        ) as z_statistic,

        -- Half-width of the 95% CI for the difference (each group has its own variance)
        1.96 * sqrt(
            control_rate * (1 - control_rate) / control_n
            + treatment_rate * (1 - treatment_rate) / treatment_n
        ) as diff_margin,

        -- Sample ratio check: for an expected 50/50 split this simplifies to d^2 / N
        pow(cast(treatment_assigned - control_assigned as double), 2)
            / (treatment_assigned + control_assigned) as srm_chi_square

    from rates

),

decided as (

    -- Decisions are computed from the unrounded numbers
    select
        *,
        abs(z_statistic) > 1.96 as is_significant_5pct,
        srm_chi_square > 10.83 as has_sample_ratio_mismatch
    from stats

)

select
    experiment_name,
    control_assigned,
    treatment_assigned,
    control_n as control_mature_users,
    treatment_n as treatment_mature_users,
    control_converted,
    treatment_converted,
    round(control_rate, 4) as control_rate,
    round(treatment_rate, 4) as treatment_rate,
    round(absolute_lift, 4) as absolute_lift,
    round(relative_lift, 4) as relative_lift,
    round(absolute_lift - diff_margin, 4) as lift_ci_low,
    round(absolute_lift + diff_margin, 4) as lift_ci_high,
    round(z_statistic, 3) as z_statistic,
    is_significant_5pct,
    round(srm_chi_square, 3) as srm_chi_square,
    has_sample_ratio_mismatch,

    -- Plain-English decision. The SRM check comes first: if randomisation is
    -- broken, nothing else matters.
    case
        when has_sample_ratio_mismatch
            then 'Do not trust: sample ratio mismatch'
        when is_significant_5pct and absolute_lift > 0
            then 'Ship treatment: significant improvement'
        when is_significant_5pct and absolute_lift < 0
            then 'Do not ship: treatment is worse'
        else 'Inconclusive: no significant difference'
    end as recommendation

from decided