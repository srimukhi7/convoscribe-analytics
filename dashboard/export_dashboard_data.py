"""
export_dashboard_data.py

Exports the finished metric, quality and experiment tables from DuckDB to small
CSV files in dashboard/data/. The hosted dashboard reads these files, because the
DuckDB database lives on this laptop and is not available to the web host.

The CSVs contain only aggregated numbers, never user-level rows or emails.

Run from the project root (after dbt build):
    python dashboard/export_dashboard_data.py
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "convoscribe.duckdb"
OUT_DIR = Path(__file__).resolve().parent / "data"

# CSV file name -> table in DuckDB (schema.table, as created by dbt)
TABLES = {
    "metrics_weekly_active_users": "metrics.metrics_weekly_active_users",
    "metrics_activation": "metrics.metrics_activation",
    "metrics_conversion": "metrics.metrics_conversion",
    "metrics_mrr_monthly": "metrics.metrics_mrr_monthly",
    "metrics_cohort_retention": "metrics.metrics_cohort_retention",
    "exp_variant_results": "experiments.exp_variant_results",
    "exp_readout": "experiments.exp_readout",
    "dq_daily_anomalies": "quality.dq_daily_anomalies",
    "dq_scorecard": "quality.dq_scorecard",
    "dq_source_freshness": "quality.dq_source_freshness",
}

# Extra small summaries built with SQL (aggregated only)
QUERIES = {
    "plan_mix": """
        select current_plan, count(*) as users
        from marts.dim_users
        group by 1
        order by users desc
    """,
}


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # read_only: we only read from the database, never change it
    con = duckdb.connect(str(DB_PATH), read_only=True)

    for name, table in TABLES.items():
        df = con.execute(f"select * from {table}").df()
        df.to_csv(OUT_DIR / f"{name}.csv", index=False)
        print(f"  {name}.csv: {len(df):,} rows")

    for name, query in QUERIES.items():
        df = con.execute(query).df()
        df.to_csv(OUT_DIR / f"{name}.csv", index=False)
        print(f"  {name}.csv: {len(df):,} rows")

    con.close()


if __name__ == "__main__":
    main()