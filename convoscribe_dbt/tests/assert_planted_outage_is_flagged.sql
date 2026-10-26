-- Testing the test: we planted a logging outage on 2026-03-18 in the data generator.
-- If the anomaly detector does NOT flag it, this test returns a row and fails.
-- A detector that has never been shown a real failure proves nothing.

select 'planted outage on 2026-03-18 was not flagged' as problem
from (select 1) as one
where not exists (
    select 1
    from {{ ref('dq_daily_anomalies') }}
    where activity_date = date '2026-03-18'
      and metric_name = 'meetings'
      and is_anomaly
)