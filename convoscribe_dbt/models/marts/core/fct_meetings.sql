-- fct_meetings: the source of truth for meetings.
-- Grain: one row per VALID meeting.
-- Excluded on purpose (flagged in staging, removed here):
--   * meetings with a duration of zero or less
--   * meetings whose user_id does not exist (the inner join drops them)
-- A reconciliation test proves staged = included + excluded.

with meetings as (

    select *
    from {{ ref('stg_meetings') }}
    where is_valid_duration

),

users as (

    select user_id, workspace_id, signed_up_at
    from {{ ref('stg_users') }}

)

select
    m.meeting_id,
    m.user_id,
    u.workspace_id,
    m.started_at,
    cast(m.started_at as date) as meeting_date,
    m.duration_minutes,
    m.platform,
    m.participant_count,
    m.language_code,
    m.ingested_at,
    m.is_late_arriving,
    -- Days between signup and this meeting (used for retention metrics)
    date_diff('day', cast(u.signed_up_at as date), cast(m.started_at as date)) as days_since_signup

from meetings as m
inner join users as u on u.user_id = m.user_id