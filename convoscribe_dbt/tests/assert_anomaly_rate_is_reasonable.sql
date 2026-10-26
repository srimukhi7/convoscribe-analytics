-- Alert-fatigue guard: if more than 5% of evaluated day-metrics are flagged,
-- the thresholds are too sensitive to be useful. Returns a row (fails) if so.

select
    count(*) filter (where is_anomaly) as flagged_days,
    count(*) filter (where is_evaluated) as evaluated_days
from {{ ref('dq_daily_anomalies') }}
having count(*) filter (where is_anomaly) > 0.05 * count(*) filter (where is_evaluated)