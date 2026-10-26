"""
load_to_duckdb.py

Loads the raw CSV files into a local DuckDB database file, in a schema
called "raw". This is the "L" in ELT: data is loaded exactly as it arrived,
with no cleaning. dbt does the transformation afterwards.

Safe to re-run: each table is replaced, never appended to (idempotent).

Run from the project root:
    python data_generation/load_to_duckdb.py
"""

from pathlib import Path

import duckdb

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"
DB_PATH = PROJECT_ROOT / "data" / "convoscribe.duckdb"

RAW_TABLES = [
    "raw_users",
    "raw_workspaces",
    "raw_meetings",
    "raw_feature_events",
    "raw_subscription_events",
    "raw_experiment_assignments",
]


def main():
    # Connecting to a file path creates the database file if it doesn't exist
    con = duckdb.connect(str(DB_PATH))
    con.execute("create schema if not exists raw")

    for table in RAW_TABLES:
        csv_path = RAW_DIR / f"{table}.csv"
        if not csv_path.exists():
            raise FileNotFoundError(f"{csv_path} not found. Run generate_data.py first.")

        # "create or replace" makes the load idempotent.
        # read_csv_auto detects column types (numbers, timestamps, text);
        # sample_size = -1 makes it scan the whole file, not just the top rows.
        con.execute(f"""
            create or replace table raw.{table} as
            select * from read_csv_auto('{csv_path.as_posix()}',
                                        header = true, sample_size = -1)
        """)
        n_rows = con.execute(f"select count(*) from raw.{table}").fetchone()[0]
        print(f"  raw.{table}: {n_rows:,} rows")

    # Show the column types DuckDB detected for one table, as a sanity check
    print("\nDetected column types for raw.raw_meetings:")
    print(con.execute("describe raw.raw_meetings").df()[["column_name", "column_type"]])

    con.close()   # release the file so dbt can open it


if __name__ == "__main__":
    main()