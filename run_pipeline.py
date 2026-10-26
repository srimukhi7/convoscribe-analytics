"""
run_pipeline.py: rebuild the whole project with one command.

    python run_pipeline.py

Steps: generate raw data -> load into DuckDB -> dbt build (models and tests)
-> export the dashboard data. Stops at the first failing step, so a failing
data test blocks the export. Failing loudly is what a real pipeline should do.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DBT_DIR = ROOT / "convoscribe_dbt"

# (label, command, folder to run it in)
STEPS = [
    ("1/4 Generate raw data", [sys.executable, "data_generation/generate_data.py"], ROOT),
    ("2/4 Load into DuckDB", [sys.executable, "data_generation/load_to_duckdb.py"], ROOT),
    ("3/4 Build and test with dbt", ["dbt", "build"], DBT_DIR),
    ("4/4 Export dashboard data", [sys.executable, "dashboard/export_dashboard_data.py"], ROOT),
]


def main():
    for label, command, folder in STEPS:
        print(f"\n=== {label} ===")
        result = subprocess.run(command, cwd=folder)
        if result.returncode != 0:
            sys.exit(f"\nStep failed: {label}. Fix the error above and re-run.")
    print("\nPipeline finished. View the dashboard with: streamlit run dashboard/app.py")


if __name__ == "__main__":
    main()