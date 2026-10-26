-- Rule: the grain of fct_daily_activity is one row per user per day.

select user_id, activity_date, count(*) as row_count
from {{ ref('fct_daily_activity') }}
group by user_id, activity_date
having count(*) > 1