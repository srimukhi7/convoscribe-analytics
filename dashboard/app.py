"""
ConvoScribe analytics dashboard (Streamlit).

Reads the CSV files exported by export_dashboard_data.py and shows revenue,
engagement, an A/B test readout and data quality. Every number comes from the
governed dbt models; the only calculation done here is a p-value for display.

Run locally from the project root:
    streamlit run dashboard/app.py
"""

from math import erfc, sqrt
from pathlib import Path

import altair as alt
import pandas as pd
import streamlit as st

REPO_URL = "https://github.com/srimukhi7/convoscribe-analytics"
DATA_DIR = Path(__file__).resolve().parent / "data"

st.set_page_config(page_title="ConvoScribe Analytics", page_icon="📊", layout="wide")


@st.cache_data
def load(name, date_cols=()):
    """Read one exported CSV. Cached, so it loads once rather than on every click."""
    return pd.read_csv(DATA_DIR / f"{name}.csv", parse_dates=list(date_cols))


# -----------------------------------------------------------------------------
# Chart helpers
# Streamlit's built-in st.line_chart / st.bar_chart cannot control label angles
# or force the y axis to start at zero, so we draw simple charts with Altair.
# -----------------------------------------------------------------------------
def line_chart(data, x, y, y_title, y_format=",.0f", date_format="%b %y",
               zero=False, height=280):
    """Line chart over time: horizontal date labels, formatted y axis."""
    chart = (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{x}:T", title=None,
                    axis=alt.Axis(format=date_format, labelAngle=0, labelOverlap=True)),
            y=alt.Y(f"{y}:Q", title=y_title,
                    axis=alt.Axis(format=y_format),
                    scale=alt.Scale(zero=zero)),   # zero=True forces the axis to start at 0
            tooltip=[alt.Tooltip(f"{x}:T", title="Date", format="%b %d, %Y"),
                     alt.Tooltip(f"{y}:Q", title=y_title, format=y_format)],
        )
        .properties(height=height, width="container")
    )
    st.altair_chart(chart)


def bar_chart(data, x, y, y_title, y_format=",.0f", sort=None, height=280):
    """Bar chart over categories: horizontal labels, y axis always starts at zero."""
    chart = (
        alt.Chart(data)
        .mark_bar()
        .encode(
            x=alt.X(f"{x}:N", title=None, sort=sort,
                    axis=alt.Axis(labelAngle=0)),
            y=alt.Y(f"{y}:Q", title=y_title,
                    axis=alt.Axis(format=y_format),
                    scale=alt.Scale(zero=True)),   # bars must start at zero to be honest
            tooltip=[alt.Tooltip(f"{x}:N", title="Category"),
                     alt.Tooltip(f"{y}:Q", title=y_title, format=y_format)],
        )
        .properties(height=height, width="container")
    )
    st.altair_chart(chart)


# -----------------------------------------------------------------------------
# Load data
# -----------------------------------------------------------------------------
mrr = load("metrics_mrr_monthly", ("month_start",)).sort_values("month_start")
wau = load("metrics_weekly_active_users", ("week_start",)).sort_values("week_start")
activation = load("metrics_activation", ("signup_week",)).sort_values("signup_week")
conversion = load("metrics_conversion", ("signup_month",)).sort_values("signup_month")
cohorts = load("metrics_cohort_retention", ("cohort_month",))
variants = load("exp_variant_results")
readout = load("exp_readout")
anomalies = load("dq_daily_anomalies", ("activity_date",))
scorecard = load("dq_scorecard")
freshness = load("dq_source_freshness", ("latest_event_at", "latest_ingested_at"))
plan_mix = load("plan_mix")

# -----------------------------------------------------------------------------
# Header and headline numbers
# -----------------------------------------------------------------------------
st.title("📊 ConvoScribe Analytics")
st.caption(
    "Synthetic data for a fictional AI meeting-assistant app. "
    "Built with Python, dbt Core and DuckDB. "
    f"[Source code on GitHub]({REPO_URL})"
)

latest, prior = mrr.iloc[-1], mrr.iloc[-2]
complete_weeks = wau[wau["is_complete_week"]]
latest_week = complete_weeks.iloc[-1]
latest_conversion = conversion.dropna(subset=["conversion_rate"]).iloc[-1]

k1, k2, k3, k4, k5 = st.columns(5)
k1.metric(
    f"MRR ({latest['month_start']:%b %Y})",
    f"${latest['ending_mrr']:,.0f}",
    f"{latest['ending_mrr'] - prior['ending_mrr']:+,.0f} vs prior month",
)
k2.metric(
    "Paying customers",
    f"{int(latest['paying_customers']):,}",
    f"{int(latest['paying_customers'] - prior['paying_customers']):+,}",
)
k3.metric(
    "Weekly active users",
    f"{int(latest_week['weekly_active_users']):,}",
    help=f"Week of {latest_week['week_start']:%b %d, %Y}, the latest complete week.",
)
k4.metric(
    "30-day conversion",
    f"{latest_conversion['conversion_rate']:.1%}",
    help=f"Signup month {latest_conversion['signup_month']:%b %Y}, the latest month "
    "whose users have all had 30 days to convert.",
)
k5.metric(
    "Net revenue retention",
    f"{latest['net_revenue_retention']:.0%}",
    help="Revenue now from last month's customers, as a share of what they paid then.",
)

tab_rev, tab_eng, tab_exp, tab_dq, tab_defs = st.tabs(
    ["💰 Revenue", "👥 Engagement", "🧪 Experiment", "✅ Data quality", "📖 Definitions"]
)

# -----------------------------------------------------------------------------
# Revenue tab
# -----------------------------------------------------------------------------
with tab_rev:
    st.subheader("MRR movement by month")
    st.caption(
        "Bars above zero add revenue (new, expansion). Bars below zero remove it "
        "(contraction, churn)."
    )

    bridge = mrr[["month_start", "new_mrr", "expansion_mrr",
                  "contraction_mrr", "churned_mrr"]].rename(columns={
        "new_mrr": "New", "expansion_mrr": "Expansion",
        "contraction_mrr": "Contraction", "churned_mrr": "Churned"})
    bridge["Contraction"] = -bridge["Contraction"]   # show losses below zero
    bridge["Churned"] = -bridge["Churned"]
    bridge = bridge.melt("month_start", var_name="movement", value_name="mrr_change")

    colors = alt.Scale(
        domain=["New", "Expansion", "Contraction", "Churned"],
        range=["#2e7d32", "#81c784", "#ffb74d", "#e53935"],
    )
    bridge_chart = alt.Chart(bridge).mark_bar().encode(
        x=alt.X("yearmonth(month_start):T", title=None,
                axis=alt.Axis(format="%b %y", labelAngle=0)),
        y=alt.Y("mrr_change:Q", title="MRR change ($)", axis=alt.Axis(format="$,.0f")),
        color=alt.Color("movement:N", scale=colors, title="Movement"),
        tooltip=[
            alt.Tooltip("yearmonth(month_start):T", title="Month"),
            alt.Tooltip("movement:N", title="Movement"),
            alt.Tooltip("mrr_change:Q", title="MRR change ($)", format=",.0f"),
        ],
    ).properties(height=320, width="container")
    st.altair_chart(bridge_chart)

    left, right = st.columns(2)
    with left:
        st.subheader("Ending MRR ($)")
        st.caption("Total monthly recurring revenue at the end of each month. A rising line means the business is growing.")
        line_chart(mrr, "month_start", "ending_mrr", "Ending MRR",
                   y_format="$,.0f", zero=True)
    with right:
        st.subheader("Customers by plan today")
        st.caption("Includes the free plan. Most users never upgrade, as in most freemium products.")
        bar_chart(plan_mix, "current_plan", "users", "Users",
                  sort=["free", "pro", "business"])

    # Early months have too few customers for stable rates, so we hide them
    stable = mrr[mrr["starting_customers"] >= 5]
    left, right = st.columns(2)
    with left:
        st.subheader("Monthly logo churn rate")
        st.caption("Share of customers at the start of each month who left during it. Lower is better. Early months with fewer than 5 customers are hidden because the rate is too noisy.")
        line_chart(stable, "month_start", "logo_churn_rate", "Logo churn",
                   y_format=".0%", zero=True)
    with right:
        st.subheader("Net revenue retention")
        st.caption("Revenue now from last month's customers, as a share of what they paid then. Above 100% means expansion outweighs churn and contraction.")
        line_chart(stable, "month_start", "net_revenue_retention", "NRR",
                   y_format=".0%")

# -----------------------------------------------------------------------------
# Engagement tab
# -----------------------------------------------------------------------------
with tab_eng:
    left, right = st.columns(2)
    with left:
        st.subheader("Weekly active users")
        st.caption("Complete weeks only, so the partial first and last weeks do not look like dips.")
        line_chart(complete_weeks, "week_start", "weekly_active_users",
                   "Weekly active users", zero=True)
    with right:
        st.subheader("Meetings per active user")
        st.caption("Average meetings per active user each week. Higher means people are leaning on the product more.")
        line_chart(complete_weeks, "week_start", "meetings_per_active_user",
                   "Meetings per active user", y_format=".1f")

    left, right = st.columns(2)
    with left:
        st.subheader("Activation rate by signup week")
        st.caption("3+ meetings within 14 days of signup. Recent weeks are blank until users have had 14 days.")
        line_chart(activation.dropna(subset=["activation_rate"]),
                   "signup_week", "activation_rate", "Activation rate", y_format=".0%")
    with right:
        st.subheader("30-day free-to-paid conversion by signup month")
        st.caption("Share of each signup month's users who started a paid plan within 30 days. Recent months are hidden until all their users have had 30 days.")
        conv = conversion.dropna(subset=["conversion_rate"]).copy()
        conv["month"] = conv["signup_month"].dt.strftime("%b %y")   # text labels stay horizontal
        bar_chart(conv, "month", "conversion_rate", "30-day conversion",
                  y_format=".0%", sort=list(conv["month"]))

    st.subheader("Cohort retention")
    st.caption("Share of each signup-month cohort with at least one meeting N months after signup.")
    heat = alt.Chart(cohorts).mark_rect().encode(
        x=alt.X("months_since_signup:O", title="Months since signup",
                axis=alt.Axis(labelAngle=0)),
        y=alt.Y("yearmonth(cohort_month):O", title="Signup cohort"),
        color=alt.Color("retention_rate:Q", title="Retention",
                        scale=alt.Scale(scheme="blues"),
                        legend=alt.Legend(format=".0%")),
        tooltip=[
            alt.Tooltip("yearmonth(cohort_month):O", title="Cohort"),
            alt.Tooltip("months_since_signup:O", title="Months since signup"),
            alt.Tooltip("cohort_size:Q", title="Cohort size"),
            alt.Tooltip("retained_users:Q", title="Retained users"),
            alt.Tooltip("retention_rate:Q", title="Retention", format=".1%"),
        ],
    )
    labels = heat.mark_text(fontSize=10).encode(
        text=alt.Text("retention_rate:Q", format=".0%"),
        color=alt.condition(alt.datum.retention_rate > 0.5,
                            alt.value("white"), alt.value("black")),
    )
    st.altair_chart((heat + labels).properties(height=380, width="container"))

# -----------------------------------------------------------------------------
# Experiment tab
# -----------------------------------------------------------------------------
with tab_exp:
    r = readout.iloc[0]
    z = r["z_statistic"]
    p_value = erfc(abs(z) / sqrt(2))   # two-sided p-value from the z-statistic

    st.subheader(f"A/B test: {r['experiment_name']}")
    st.caption(
        "Question: does the new upgrade prompt increase the share of new users who "
        "start a paid plan within 14 days? Only users who have had the full 14 days are counted."
    )

    e1, e2, e3, e4 = st.columns(4)
    e1.metric("Control conversion", f"{r['control_rate']:.1%}",
              help=f"{int(r['control_converted'])} of {int(r['control_mature_users'])} users")
    e2.metric("Treatment conversion", f"{r['treatment_rate']:.1%}",
              f"{r['absolute_lift'] * 100:+.1f} points",
              help=f"{int(r['treatment_converted'])} of {int(r['treatment_mature_users'])} users")
    e3.metric("Relative lift", f"{r['relative_lift']:+.0%}",
              help=f"95% CI for the difference: {r['lift_ci_low'] * 100:+.1f} to "
                   f"{r['lift_ci_high'] * 100:+.1f} points")
    e4.metric("p-value", f"{p_value:.4f}",
              help="Lower than 0.05 means significant at the 5% level.")

    st.success(f"**Recommendation:** {r['recommendation']}")

    order = ["control", "treatment"]
    bars = alt.Chart(variants).mark_bar().encode(
        x=alt.X("variant:N", title=None, sort=order, axis=alt.Axis(labelAngle=0)),
        y=alt.Y("conversion_rate:Q", title="14-day paid conversion",
                axis=alt.Axis(format="%"), scale=alt.Scale(zero=True)),
        color=alt.Color("variant:N", legend=None, sort=order),
        tooltip=["variant:N", alt.Tooltip("conversion_rate:Q", format=".2%"),
                 "converted_users:Q", "mature_users:Q"],
    )
    whiskers = alt.Chart(variants).mark_rule(strokeWidth=2).encode(
        x=alt.X("variant:N", sort=order), y="ci_low:Q", y2="ci_high:Q",
    )
    st.altair_chart((bars + whiskers).properties(height=320, width="container"))
    st.caption("Whiskers show the 95% confidence interval for each conversion rate.")

    s1, s2 = st.columns(2)
    s1.metric("Sample ratio check (chi-square)", f"{r['srm_chi_square']:.2f}",
              help="Checks the split is really 50/50. Above 10.83 would mean randomisation is broken.")
    s2.metric("Sample ratio mismatch?", "Yes" if r["has_sample_ratio_mismatch"] else "No")

# -----------------------------------------------------------------------------
# Data quality tab
# -----------------------------------------------------------------------------
with tab_dq:
    st.subheader("What the pipeline found and fixed")
    st.caption(
        "Problems deliberately planted in the raw data, detected and handled by the "
        "dbt staging layer. 100+ automated dbt tests guard the models."
    )
    st.dataframe(
        scorecard[["table_name", "issue", "measured_on",
                   "rows_affected", "total_rows", "pct_affected"]],
        hide_index=True,
    )

    st.subheader("Anomaly detection")
    # Keep this threshold text in sync with anomaly_z_threshold in dbt_project.yml
    st.caption(
        "Each day is compared with the previous 8 same weekdays. A day is flagged when the "
        "z-score is above 4 in size and the change is above 25%. Red dots are flagged days."
    )
    metric = st.selectbox("Metric", ["meetings", "active_users", "signups"])
    sub = anomalies[anomalies["metric_name"] == metric]
    flagged = sub[sub["is_anomaly"]]

    line = alt.Chart(sub).mark_line().encode(
        x=alt.X("activity_date:T", title=None,
                axis=alt.Axis(format="%b %y", labelAngle=0, labelOverlap=True)),
        y=alt.Y("metric_value:Q", title=metric, scale=alt.Scale(zero=True)),
    )
    baseline = alt.Chart(sub).mark_line(strokeDash=[4, 4], color="gray").encode(
        x="activity_date:T", y="baseline_mean:Q",
    )
    chart = line + baseline
    if not flagged.empty:
        points = alt.Chart(flagged).mark_point(size=140, filled=True, color="red").encode(
            x="activity_date:T", y="metric_value:Q",
            tooltip=["activity_date:T", "metric_value:Q", "baseline_mean:Q", "z_score:Q"],
        )
        chart = chart + points
    st.altair_chart(chart.properties(height=320, width="container"))
    st.caption("Dashed gray line: the same-weekday baseline.")

    if flagged.empty:
        st.info("No days flagged for this metric.")
    else:
        st.write("Flagged days")
        st.caption("Each row is a day that broke from its same-weekday baseline. Direction shows whether the metric spiked or dropped.")
        st.dataframe(
            flagged.assign(activity_date=flagged["activity_date"].dt.date)[
                ["activity_date", "metric_value", "baseline_mean",
                 "z_score", "pct_change_vs_baseline", "direction"]],
            hide_index=True,
        )

    st.subheader("Source freshness")
    st.caption("Hours between the newest event in each raw table and the data cutoff.")
    st.dataframe(freshness[["table_name", "latest_event_at", "hours_since_latest_event"]],
                 hide_index=True)

# -----------------------------------------------------------------------------
# Definitions tab
# -----------------------------------------------------------------------------
with tab_defs:
    st.subheader("Metric definitions")
    st.markdown(
        """
| Metric | Definition |
|---|---|
| Weekly active users | Distinct users with at least 1 valid meeting in the week |
| Activated user | At least 3 valid meetings within 14 days of signup |
| Free-to-paid conversion | Mature signups who started a paid plan within 30 days, divided by mature signups |
| MRR | Sum of monthly prices of subscriptions active at the end of the month |
| New / expansion / contraction / churned MRR | Movement in MRR versus the previous month end |
| Logo churn | Customers who left, divided by customers at the start of the month |
| Net revenue retention | (Starting MRR + expansion - contraction - churned) divided by starting MRR |
| Cohort retention | Share of a signup-month cohort with a meeting N months after signup |

A **mature** user has had the full measurement window. Recent users are excluded from
rates so recent weeks are not understated. Full definitions are in `docs/metric_dictionary.md`.
"""
    )

st.divider()
st.caption(f"Data is synthetic. Pipeline and models: [{REPO_URL}]({REPO_URL})")