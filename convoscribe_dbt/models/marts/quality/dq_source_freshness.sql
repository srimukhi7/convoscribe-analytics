-- dq_source_freshness: how recent is the newest data in each high-volume raw table?
-- Measured against the data cutoff (data_as_of), not the real clock, because our
-- dataset is a fixed snapshot. In production you would use "dbt source freshness".

with latest as (

    select
        'raw_meetings' as table_name,
        max(cast(started_at as timestamp)) as latest_event_at,
        max(cast(ingested_at as timestamp)) as latest_ingested_at
    from {{ source('raw', 'raw_meetings') }}

    union all

    select
        'raw_feature_events',
        max(cast(event_ts as timestamp)),
        max(cast(ingested_at as timestamp))
    from {{ source('raw', 'raw_feature_events') }}

    union all

    select
        'raw_subscription_events',
        max(cast(event_ts as timestamp)),
        max(cast(ingested_at as timestamp))
    from {{ source('raw', 'raw_subscription_events') }}

)

select
    table_name,
    latest_event_at,
    latest_ingested_at,
    date_diff('hour', latest_event_at, cast('{{ var("data_as_of") }}' as timestamp))
        as hours_since_latest_event
from latest