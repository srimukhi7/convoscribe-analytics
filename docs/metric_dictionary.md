# ConvoScribe Metric Dictionary

Version 1.0. Every number below is defined once, in dbt, and read from the models listed. Dashboards and analyses should use these tables and never recompute the metrics.

## Conventions

- **Data cutoff:** 2026-09-30 23:59:59 (variable data_as_of). Nothing uses the current date.
- **Valid meeting:** duration above zero and a user_id that exists. Invalid meetings are flagged in staging and excluded in fct_meetings.
- **Maturity:** rates for activation and conversion use only users who have had the full window. Recent users appear in counts but not in rates.
- **Windows** are project variables: activation 3 meetings in 14 days, conversion 30 days.

## Metrics

| Metric | Definition | Grain | Model and column | Edge cases |
|---|---|---|---|---|
| Weekly active users | Distinct users with at least 1 valid meeting in the week | Week (Monday start) | metrics_weekly_active_users.weekly_active_users | First and last weeks are partial: filter on is_complete_week |
| Meetings per active user | Valid meetings divided by weekly active users | Week | metrics_weekly_active_users.meetings_per_active_user | |
| Activated user | At least 3 valid meetings within 14 days of signup | User | dim_users.is_activated | Only meaningful when is_activation_window_complete is true |
| Activation rate | Activated users divided by mature signups | Signup week | metrics_activation.activation_rate | Blank when a week has no mature signups |
| Free-to-paid conversion | Mature signups who started a paid plan within 30 days of signup, divided by mature signups | Signup month | metrics_conversion.conversion_rate | Paying at signup counts as converted. Latest months are blank. |
| MRR | Sum of monthly prices of subscriptions active at the last second of the month | Month | metrics_mrr_monthly.ending_mrr | A user who starts and cancels within one month never appears |
| New MRR | MRR from users paying now but not at the previous month end | Month | metrics_mrr_monthly.new_mrr | A reactivation counts as new |
| Expansion MRR | Increase in MRR from users who paid last month and pay more now | Month | metrics_mrr_monthly.expansion_mrr | Pro to business upgrade |
| Contraction MRR | Decrease in MRR from users who still pay but pay less | Month | metrics_mrr_monthly.contraction_mrr | Business to pro downgrade |
| Churned MRR | Last month's MRR from users who pay nothing now | Month | metrics_mrr_monthly.churned_mrr | |
| Logo churn rate | Customers who churned divided by customers at the start of the month | Month | metrics_mrr_monthly.logo_churn_rate | Blank when there were no starting customers |
| Net revenue retention | (Starting MRR + expansion - contraction - churned) divided by starting MRR | Month | metrics_mrr_monthly.net_revenue_retention | Excludes new customers. Can exceed 100%. |
| Cohort retention | Share of a signup-month cohort with at least 1 valid meeting N calendar months after signup | Signup month by N | metrics_cohort_retention.retention_rate | Month 0 is below 100%. Only fully elapsed months are shown. |

## Change process

A change to any definition is a pull request that updates this file and the model together, with the reconciliation tests passing.