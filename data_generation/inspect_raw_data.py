"""
inspect_raw_data.py
Quick checks that the planted data problems are really present in the raw CSVs.
Run from the project root:  python data_generation/inspect_raw_data.py
"""

from pathlib import Path

import pandas as pd

RAW = Path(__file__).resolve().parent.parent / "data" / "raw"

users = pd.read_csv(RAW / "raw_users.csv")
meetings = pd.read_csv(RAW / "raw_meetings.csv", parse_dates=["started_at"])
events = pd.read_csv(RAW / "raw_feature_events.csv")

print("--- raw_users ---")
print("Duplicate user_id rows:", users["user_id"].duplicated().sum())
print("Missing emails:", users["email"].isna().sum())
print("Emails containing capital letters:",
      users["email"].dropna().str.contains("[A-Z]").sum())

print("\n--- raw_meetings ---")
print("Duplicate meeting_id rows:", meetings["meeting_id"].duplicated().sum())
print("Meetings with duration <= 0:", (meetings["duration_minutes"] <= 0).sum())
print("Meetings with an unknown user_id:",
      (~meetings["user_id"].isin(users["user_id"])).sum())

print("\n--- raw_feature_events ---")
print("Distinct event_name spellings:", events["event_name"].nunique(),
      "(a clean table would have 4)")

print("\n--- Meetings per day around the outage (2026-03-18) ---")
daily = meetings.set_index("started_at").resample("D").size()
print(daily["2026-03-14":"2026-03-22"])