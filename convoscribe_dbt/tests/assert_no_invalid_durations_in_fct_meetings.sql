-- Rule (from the tracking plan): every meeting in the mart has a duration above zero.

select meeting_id, duration_minutes
from {{ ref('fct_meetings') }}
where duration_minutes <= 0