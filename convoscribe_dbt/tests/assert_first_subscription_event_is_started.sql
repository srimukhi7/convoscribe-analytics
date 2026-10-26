-- Rule: every user's first subscription event must be "started".
-- Our period logic assumes this. Returns any user who breaks it.

select user_id
from (
    select
        user_id,
        event_type,
        row_number() over (
            partition by user_id order by occurred_at, subscription_event_id
        ) as event_order
    from {{ ref('stg_subscription_events') }}
) as ordered
where event_order = 1
  and event_type <> 'started'