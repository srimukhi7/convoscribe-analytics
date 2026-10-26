-- Rule 1: one row per cohort and month offset.
select cohort_month, months_since_signup, 'duplicate_grain' as problem
from {{ ref('metrics_cohort_retention') }}
group by cohort_month, months_since_signup
having count(*) > 1

union all

-- Rule 2: retained users can never exceed the cohort size.
select cohort_month, months_since_signup, 'retained_exceeds_cohort' as problem
from {{ ref('metrics_cohort_retention') }}
where retained_users > cohort_size