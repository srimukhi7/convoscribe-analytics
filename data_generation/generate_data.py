"""
generate_data.py

Generates the six RAW tables for ConvoScribe, a fictional AI meeting-notes app.

Pattern: "clean truth, then damage a copy"
  1. Simulate a clean, internally consistent dataset (users, meetings, events,
     subscriptions, an A/B test).
  2. Copy each table and deliberately damage the copy (duplicates, missing
     values, inconsistent names...) the way real production data is messy.
  3. Write the damaged copies to data/raw/ as CSV files.

dbt cleans the damaged data later, and tests catch the problems we planted.

Run from the project root:
    python data_generation/generate_data.py
"""

from pathlib import Path

import numpy as np
import pandas as pd
from faker import Faker

# =============================================================================
# 1. CONFIGURATION  (change settings here, not deep inside the code)
# =============================================================================
SEED = 42                      # same seed -> identical data on every run
N_USERS = 5000
START_DATE = pd.Timestamp("2025-10-01")            # earliest possible signup
END_DATE = pd.Timestamp("2026-09-30 23:59:59")     # data "as of" cutoff

# CSVs are written to <project root>/data/raw
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

# Illustrative monthly prices in USD (not any real company's pricing)
PRICES = {"pro": 15.0, "business": 35.0}

# Usage behaviour
BASE_MEETINGS_PER_DAY = 0.30   # weekday meetings for a "typical" user
WEEKEND_FACTOR = 0.15          # weekends have 15% of weekday activity
PAID_USAGE_BOOST = 1.4         # paying users hold 40% more meetings

# A/B test: new upgrade prompt shown to half of users who sign up after the start
EXPERIMENT_NAME = "upgrade_prompt_v2"
EXPERIMENT_START = pd.Timestamp("2026-04-01")
TREATMENT_LOGIT_BOOST = 0.5    # how much the new prompt raises upgrade odds

# A planted logging outage: almost no events are recorded on this day
OUTAGE_DATE = pd.Timestamp("2026-03-18")
OUTAGE_KEEP_FRACTION = 0.03    # only 3% of that day's rows survive

# Event types logged by the app, with the chance each follows a meeting
FEATURE_EVENTS = {
    "summary_viewed": 0.60,
    "action_item_created": 0.30,
    "transcript_shared": 0.15,
    "ai_chat_used": 0.25,
}

rng = np.random.default_rng(SEED)   # seeded random number generator
Faker.seed(SEED)
fake = Faker()                      # generates fake emails and company names


# =============================================================================
# 2. SMALL HELPER FUNCTIONS
# =============================================================================
def add_ingestion_time(event_ts, late_fraction=0.01):
    """
    Simulate WHEN each row reached our warehouse (ingested_at).
    Normally seconds after the event; for ~1% of rows it arrives 1-5 days
    late (late-arriving data).
    """
    n = len(event_ts)
    delay_seconds = rng.integers(5, 600, size=n).astype(float)
    is_late = rng.random(n) < late_fraction
    delay_seconds[is_late] = rng.uniform(1, 5, size=is_late.sum()) * 86400
    return event_ts.to_numpy() + pd.to_timedelta(delay_seconds, unit="s").to_numpy()


def apply_outage(df, ts_col):
    """Drop ~97% of the rows that fall on the outage day (simulates a logging failure)."""
    on_outage_day = df[ts_col].dt.normalize() == OUTAGE_DATE
    survives = ~on_outage_day | (rng.random(len(df)) < OUTAGE_KEEP_FRACTION)
    return df[survives].reset_index(drop=True)


# =============================================================================
# 3. BUILD THE CLEAN TABLES
# =============================================================================
def build_users():
    """Create users, plus a hidden 'engagement' score that drives their behaviour."""
    # Sorted random positions through the year. beta(1.5, 1) leans toward later
    # dates, so signups GROW over time like a growing startup.
    position = np.sort(rng.beta(1.5, 1.0, size=N_USERS))
    total_seconds = (END_DATE - START_DATE).total_seconds()
    signup_ts = (START_DATE + pd.to_timedelta(position * total_seconds, unit="s")).floor("s")

    users = pd.DataFrame({
        "user_id": [f"u_{i:05d}" for i in range(1, N_USERS + 1)],
        # Adding the number guarantees every email is unique
        "email": [f"{fake.user_name()}{i}@{fake.free_email_domain()}"
                  for i in range(1, N_USERS + 1)],
        "signup_ts": signup_ts,
        "country": rng.choice(["US", "CA", "GB", "IN", "DE", "AU", "BR", "FR"],
                              size=N_USERS,
                              p=[0.40, 0.08, 0.10, 0.14, 0.07, 0.06, 0.08, 0.07]),
        "signup_source": rng.choice(["organic", "paid_search", "referral", "partner"],
                                    size=N_USERS, p=[0.45, 0.25, 0.20, 0.10]),
        "device": rng.choice(["web", "ios", "android", "desktop_app"],
                             size=N_USERS, p=[0.45, 0.20, 0.15, 0.20]),
    })

    # Hidden engagement: average 1.0. Higher = more meetings, stays longer, upgrades more.
    engagement = rng.gamma(shape=2.0, scale=0.5, size=N_USERS)
    return users, engagement


def build_workspaces(users):
    """About 35% of users belong to a team workspace; the rest are solo users."""
    workspace_ids = [f"w_{i:04d}" for i in range(1, 601)]
    in_workspace = rng.random(N_USERS) < 0.35
    picked = rng.choice(workspace_ids, size=N_USERS)
    users["workspace_id"] = np.where(in_workspace, picked, None)

    # A workspace is "created" when its first member signs up
    members = users.dropna(subset=["workspace_id"])
    workspaces = members.groupby("workspace_id", as_index=False).agg(
        created_ts=("signup_ts", "min")
    )
    workspaces["workspace_name"] = [fake.company() for _ in range(len(workspaces))]
    workspaces["plan_at_creation"] = rng.choice(
        ["free", "pro", "business"], size=len(workspaces), p=[0.80, 0.15, 0.05]
    )
    return users, workspaces[["workspace_id", "workspace_name", "created_ts", "plan_at_creation"]]


def build_experiment(users):
    """Randomly split users who signed up after EXPERIMENT_START into control / treatment."""
    in_experiment = (users["signup_ts"] >= EXPERIMENT_START).to_numpy()
    variant = np.where(rng.random(N_USERS) < 0.5, "treatment", "control")

    assignments = pd.DataFrame({
        "user_id": users["user_id"],
        "experiment_name": EXPERIMENT_NAME,
        "variant": variant,
        "assigned_ts": users["signup_ts"],      # assigned at signup
    })[in_experiment].reset_index(drop=True)

    # True only for users in the experiment AND in the treatment group
    is_treated = in_experiment & (variant == "treatment")
    return assignments, is_treated


def build_subscriptions(users, engagement, is_treated):
    """
    Decide who upgrades to a paid plan and simulate their plan history.
    Returns the subscription events and each payer's paid window (used to
    make paying users slightly more active).
    """
    # Chance of upgrading: higher for engaged users, and higher for users who
    # saw the new prompt. "logit" is just a way to keep probabilities in 0-1.
    logit = -2.6 + 1.2 * (engagement - 1.0) + TREATMENT_LOGIT_BOOST * is_treated
    p_convert = 1 / (1 + np.exp(-logit))
    converts = rng.random(N_USERS) < p_convert

    # Days from signup to upgrade: usually soon, sometimes much later
    delay_days = rng.exponential(12, size=N_USERS)
    signup_np = users["signup_ts"].to_numpy()
    paid_start = pd.DatetimeIndex(
        signup_np + pd.to_timedelta(delay_days, unit="D").to_numpy()
    ).floor("s")

    rows = []
    paid_window = {}   # user index -> (first paid day, last paid day)
    for i in np.where(converts)[0]:
        t0 = paid_start[i]
        if t0 > END_DATE:
            continue                          # upgrade would be after our data ends

        user_id = users.at[i, "user_id"]
        plan = "pro" if rng.random() < 0.80 else "business"
        events = [(t0, "started", plan)]

        # How long they stay paid: engaged users stay longer (minimum 3 days)
        life_days = 3 + rng.exponential(100 * engagement[i] + 30)
        cancel_ts = t0 + pd.Timedelta(days=life_days)

        # 12% change plan once between starting and cancelling
        if rng.random() < 0.12:
            change_ts = t0 + (cancel_ts - t0) * rng.random()
            if change_ts <= END_DATE:
                plan = "business" if plan == "pro" else "pro"
                events.append((change_ts, "upgraded" if plan == "business" else "downgraded", plan))

        paid_end = END_DATE
        if cancel_ts <= END_DATE:
            events.append((cancel_ts, "cancelled", plan))
            paid_end = cancel_ts
            # 10% of cancellers come back 2-13 weeks later
            if rng.random() < 0.10:
                react_ts = cancel_ts + pd.Timedelta(days=rng.uniform(14, 90))
                if react_ts <= END_DATE:
                    events.append((react_ts, "reactivated", plan))

        paid_window[i] = (t0.normalize(), paid_end.normalize())
        for ts, event_type, event_plan in events:
            rows.append({
                "user_id": user_id,
                "event_type": event_type,
                "plan": event_plan,
                "monthly_price": PRICES[event_plan],
                "event_ts": ts,
            })

    subs = pd.DataFrame(rows)
    subs["event_ts"] = subs["event_ts"].dt.floor("s")
    subs = subs.sort_values("event_ts").reset_index(drop=True)
    subs.insert(0, "subscription_event_id", [f"s_{k:06d}" for k in range(1, len(subs) + 1)])
    subs["ingested_at"] = add_ingestion_time(subs["event_ts"])
    return subs, paid_window


def build_meetings(users, engagement, paid_window):
    """Simulate day-by-day meeting activity for every user."""
    signup_np = users["signup_ts"].to_numpy()
    end_np = END_DATE.to_datetime64()
    business_hours = np.arange(8, 19)   # meetings start between 08:00 and 18:59
    hour_weights = [0.05, 0.12, 0.14, 0.12, 0.08, 0.09, 0.12, 0.12, 0.09, 0.05, 0.02]

    user_idx_parts, start_parts = [], []
    for i in range(N_USERS):
        # How many days this user stays active after signing up
        active_days = int(rng.exponential(70 * engagement[i] + 10)) + 1
        first_day = users.at[i, "signup_ts"].normalize()
        last_day = min(first_day + pd.Timedelta(days=active_days), END_DATE.normalize())
        days = pd.date_range(first_day, last_day, freq="D")

        # Expected meetings per day: weekdays busy, weekends quiet
        weekday_factor = np.where(days.dayofweek < 5, 1.0, WEEKEND_FACTOR)
        rate = BASE_MEETINGS_PER_DAY * engagement[i] * weekday_factor
        if i in paid_window:                          # paying users are more active
            paid_from, paid_to = paid_window[i]
            in_paid = (days >= paid_from) & (days <= paid_to)
            rate = np.where(in_paid, rate * PAID_USAGE_BOOST, rate)

        # Poisson = random whole numbers that average out to the expected rate
        counts = rng.poisson(rate)
        total = int(counts.sum())
        if total == 0:
            continue

        # Give each meeting a start time on its day
        day_values = np.repeat(days.to_numpy(), counts)
        hours = rng.choice(business_hours, size=total, p=hour_weights)
        minutes = rng.integers(0, 60, size=total)
        seconds = rng.integers(0, 60, size=total)
        started = (day_values
                   + hours.astype("timedelta64[h]")
                   + minutes.astype("timedelta64[m]")
                   + seconds.astype("timedelta64[s]"))

        # A meeting cannot start before the user signed up or after the cutoff
        keep = (started >= signup_np[i]) & (started <= end_np)
        user_idx_parts.append(np.full(int(keep.sum()), i))
        start_parts.append(started[keep])

    meetings = pd.DataFrame({
        "user_idx": np.concatenate(user_idx_parts),
        "started_at": np.concatenate(start_parts),
    })
    meetings = apply_outage(meetings, "started_at")
    meetings = meetings.sort_values("started_at").reset_index(drop=True)

    n = len(meetings)
    meetings.insert(0, "meeting_id", [f"m_{k:06d}" for k in range(1, n + 1)])
    meetings["user_id"] = users["user_id"].to_numpy()[meetings["user_idx"].to_numpy()]
    # Durations: most meetings ~30 minutes, a few very long. Clipped to 3-240.
    meetings["duration_minutes"] = np.clip(
        np.round(rng.lognormal(mean=3.4, sigma=0.55, size=n)), 3, 240
    ).astype(int)
    meetings["platform"] = rng.choice(
        ["zoom", "google_meet", "microsoft_teams", "in_person"],
        size=n, p=[0.45, 0.25, 0.22, 0.08])
    meetings["participant_count"] = 1 + rng.poisson(3.5, size=n)
    meetings["language"] = rng.choice(
        ["en", "es", "de", "fr", "pt"], size=n, p=[0.85, 0.06, 0.03, 0.03, 0.03])
    meetings["ingested_at"] = add_ingestion_time(meetings["started_at"])

    return meetings[["meeting_id", "user_id", "started_at", "duration_minutes",
                     "platform", "participant_count", "language", "ingested_at"]]


def build_feature_events(meetings):
    """After each meeting, users sometimes use AI features (view summary, etc.)."""
    parts = []
    for event_name, probability in FEATURE_EVENTS.items():
        picked = rng.random(len(meetings)) < probability
        part = meetings.loc[
            picked, ["meeting_id", "user_id", "started_at", "duration_minutes"]
        ].copy()
        # Usually happens soon after the meeting ends, occasionally days later
        delay_minutes = np.minimum(rng.exponential(180, size=len(part)), 2880)
        part["event_ts"] = part["started_at"] + pd.to_timedelta(
            part["duration_minutes"] + delay_minutes, unit="min")
        part["event_name"] = event_name
        if event_name == "ai_chat_used":
            # 25% of chat questions span many meetings, so no meeting_id
            part.loc[rng.random(len(part)) < 0.25, "meeting_id"] = None
        parts.append(part)

    events = pd.concat(parts, ignore_index=True)
    events = events[events["event_ts"] <= END_DATE]
    events = apply_outage(events, "event_ts")
    events = events.sort_values("event_ts").reset_index(drop=True)
    events.insert(0, "event_id", [f"e_{k:07d}" for k in range(1, len(events) + 1)])
    events["ingested_at"] = add_ingestion_time(events["event_ts"])
    return events[["event_id", "user_id", "event_name", "event_ts",
                   "meeting_id", "ingested_at"]]


# =============================================================================
# 4. DAMAGE THE COPIES (the planted data problems)
# =============================================================================
def add_retry_duplicates(df, fraction, seed_offset):
    """Duplicate a few rows with the SAME id, arriving 30 minutes later (a client retry)."""
    dupes = df.sample(frac=fraction, random_state=SEED + seed_offset).copy()
    dupes["ingested_at"] = dupes["ingested_at"] + pd.Timedelta(minutes=30)
    return pd.concat([df, dupes], ignore_index=True)


def damage_users(users):
    df = users.copy()
    n = len(df)
    shout = rng.random(n) < 0.15                       # 15%: EMAIL IN CAPITALS
    df.loc[shout, "email"] = df.loc[shout, "email"].str.upper()
    padded = rng.random(n) < 0.02                      # 2%: stray spaces around email
    df.loc[padded, "email"] = "  " + df.loc[padded, "email"] + " "
    missing = rng.random(n) < 0.02                     # 2%: email missing
    df.loc[missing, "email"] = None
    dupes = df.sample(frac=0.01, random_state=SEED + 1)   # 1%: exact duplicate rows
    return pd.concat([df, dupes], ignore_index=True)


def damage_meetings(meetings):
    df = meetings.copy()
    n = len(df)
    bad_duration = rng.random(n) < 0.008               # 0.8%: zero/negative duration
    df.loc[bad_duration, "duration_minutes"] = rng.choice(
        [0, -1, -5, -30], size=int(bad_duration.sum()))
    orphan = rng.random(n) < 0.005                     # 0.5%: user does not exist
    df.loc[orphan, "user_id"] = [
        f"u_{N_USERS + int(k):05d}" for k in rng.integers(1, 300, size=int(orphan.sum()))]
    return add_retry_duplicates(df, 0.015, seed_offset=2)   # 1.5%: duplicate rows


def damage_feature_events(events):
    df = events.copy()
    n = len(df)
    messy = rng.random(n) < 0.04                       # 4%: inconsistent event names
    style = rng.integers(0, 3, size=n)
    names = df["event_name"]
    df["event_name"] = np.select(
        [messy & (style == 0), messy & (style == 1), messy & (style == 2)],
        [names.str.upper(), names.str.title(), names.str.replace("_", " ")],
        default=names)
    return add_retry_duplicates(df, 0.01, seed_offset=3)


def damage_subscriptions(subs):
    return add_retry_duplicates(subs.copy(), 0.01, seed_offset=4)


# =============================================================================
# 5. CHECKS AND OUTPUT
# =============================================================================
def print_truth_check(assignments, subs):
    """
    Print the 'true' 14-day conversion rate per variant from the CLEAN data.
    Later, our dbt experiment model should land close to these numbers.
    """
    first_paid = (subs[subs["event_type"] == "started"]
                  .groupby("user_id")["event_ts"].min())
    exp = assignments.copy()
    exp["first_paid_ts"] = exp["user_id"].map(first_paid)
    exp["converted_14d"] = (exp["first_paid_ts"].notna()
                            & (exp["first_paid_ts"] <= exp["assigned_ts"] + pd.Timedelta(days=14)))
    print("\nTRUTH CHECK - 14-day paid conversion in the A/B test (clean data):")
    print(exp.groupby("variant")["converted_14d"].agg(users="count", conversion_rate="mean"))


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Building clean data...")
    users, engagement = build_users()
    users, workspaces = build_workspaces(users)
    assignments, is_treated = build_experiment(users)
    subs, paid_window = build_subscriptions(users, engagement, is_treated)
    meetings = build_meetings(users, engagement, paid_window)
    events = build_feature_events(meetings)

    print_truth_check(assignments, subs)
    outage_count = (meetings["started_at"].dt.normalize() == OUTAGE_DATE).sum()
    week_before = (meetings["started_at"].dt.normalize() == OUTAGE_DATE - pd.Timedelta(days=7)).sum()
    print(f"\nOutage check: {outage_count} meetings on {OUTAGE_DATE.date()} "
          f"vs {week_before} on the same weekday a week earlier.")

    print("\nDamaging copies and writing CSV files...")
    raw_tables = {
        "raw_users": damage_users(users[["user_id", "email", "signup_ts", "country",
                                         "signup_source", "device", "workspace_id"]]),
        "raw_workspaces": workspaces,
        "raw_meetings": damage_meetings(meetings),
        "raw_feature_events": damage_feature_events(events),
        "raw_subscription_events": damage_subscriptions(subs),
        "raw_experiment_assignments": assignments,
    }
    for name, df in raw_tables.items():
        df.to_csv(OUTPUT_DIR / f"{name}.csv", index=False)
        print(f"  {name}.csv: {len(df):,} rows")

    print(f"\nDone. Files are in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()