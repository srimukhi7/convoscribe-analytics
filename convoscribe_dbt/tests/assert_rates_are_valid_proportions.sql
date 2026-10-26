-- Rule: proportions must lie between 0 and 1. (NRR is excluded: it can exceed 1.)

select 'activation_rate' as metric, signup_week as period, activation_rate as value
from {{ ref('metrics_activation') }}
where activation_rate < 0 or activation_rate > 1

union all

select 'conversion_rate', signup_month, conversion_rate
from {{ ref('metrics_conversion') }}
where conversion_rate < 0 or conversion_rate > 1

union all

select 'logo_churn_rate', month_start, logo_churn_rate
from {{ ref('metrics_mrr_monthly') }}
where logo_churn_rate < 0 or logo_churn_rate > 1

union all

select 'retention_rate', cohort_month, retention_rate
from {{ ref('metrics_cohort_retention') }}
where retention_rate < 0 or retention_rate > 1