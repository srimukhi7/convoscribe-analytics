# ConvoScribe Event Tracking Plan

**Version:** 1.0
**Owner:** Data Platform
**Status:** Draft

## 1. Purpose

This document defines how product events are named, what each event must contain, and when it should be logged. Following one standard means analysts can trust event data without cleaning it first, and new engineers know what "correct" logging looks like.

## 2. Naming rules

| Rule | Example | Not allowed |
|---|---|---|
| Lowercase snake_case only | summary_viewed | Summary_Viewed, summary viewed, SUMMARY_VIEWED |
| Format is object_action, action in past tense | action_item_created | create_action_item, createdActionItem |
| No spaces, no abbreviations unless universal | ai_chat_used | ai_c_u |
| Event names never contain user data | transcript_shared | transcript_shared_by_john |

## 3. Required properties on every event

| Property | Type | Description |
|---|---|---|
| event_id | string | Unique ID for the event, used to remove duplicates if the client retries |
| user_id | string | The user who performed the action |
| event_name | string | Must match a name in the catalog below |
| event_ts | timestamp (UTC) | When the action happened on the client |
| ingested_at | timestamp (UTC) | Added by the pipeline when the event is received |

## 4. Event catalog

| event_name | Fires when | Extra properties | Raw table |
|---|---|---|---|
| summary_viewed | A user opens the AI summary of a meeting | meeting_id | raw_feature_events |
| action_item_created | A user creates or accepts an AI-suggested action item | meeting_id | raw_feature_events |
| transcript_shared | A user shares a transcript link | meeting_id | raw_feature_events |
| ai_chat_used | A user asks the AI chat a question | meeting_id (optional, empty when asking across meetings) | raw_feature_events |

Meetings and subscription changes are logged in their own tables:

| Record | Fires when | Key properties | Raw table |
|---|---|---|---|
| Meeting transcribed | A meeting finishes processing | meeting_id, user_id, started_at, duration_minutes, platform, participant_count, language | raw_meetings |
| Subscription event | A user's paid plan changes | subscription_event_id, user_id, event_type, plan, monthly_price | raw_subscription_events |

Subscription event_type values: started, upgraded, downgraded, cancelled, reactivated. Free is the default state and has no event. For cancelled, plan is the plan being cancelled.

## 5. Identifiers

- user_id looks like u_00001, meeting_id like m_000001, workspace_id like w_0001.
- IDs are never reused and never change.
- A meeting must reference a user_id that exists in the users table.

## 6. Timestamps

- All timestamps are UTC, formatted YYYY-MM-DD HH:MM:SS.
- Durations are whole minutes and must be greater than zero.

## 7. Data quality expectations (tested in dbt)

- event_id, meeting_id and user_id are unique within their tables.
- event_name only contains values from the catalog.
- No meeting has a duration of zero or less.
- Every meeting and subscription event belongs to a known user.
- Events arrive within one hour of event_ts. Later arrivals are flagged as late.

## 8. Changing this plan

Any new event or changed property requires a pull request to this file, reviewed by Data Platform before it ships.