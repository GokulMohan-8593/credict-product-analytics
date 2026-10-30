# Credict: Product Analytics Case Study

End-to-end product analytics on **Credict**, a synthetic Indian neo-bank and lending super-app. The project covers the KYC funnel, retention, unit economics, credit risk and North Star metric design, using PostgreSQL and Python, with a Power BI dashboard and A/B testing to follow.

## Dataset

Synthetic data generated with Python (Faker, `en_IN` locale): about 50K users, 150K+ sessions, 686K events, 62K transactions, 2.7K BNPL orders and 6.3K loans across 15 tables. Loan default rates are calibrated to Lending Club grade-level rates.

## Modules

| # | Module | Folder |
|---|--------|--------|
| 1 | User Acquisition & KYC Funnel | `sql/01_acquisition_kyc` |
| 2 | Engagement, Retention & Cohorts | `sql/02_engagement_retention` |
| 3 | Revenue & Unit Economics | `sql/03_revenue_unit_economics` |
| 4 | Credit Risk & Health Metrics | `sql/04_credit_risk_health` |
| 5 | North Star Metric & Metric Trees | `sql/05_north_star_metric` |

## Key findings

*Coming soon.*

## Status

- [x] Schema and synthetic data generation
- [x] SQL analysis, Modules 1 to 5
- [ ] Power BI dashboard
- [ ] A/B testing module

## How to reproduce

1. Create a PostgreSQL database named `credict`.
2. Run the scripts in `sql/00_setup/` in numbered order.
3. Copy `.env.example` to `.env` and add your own connection details.
4. Install dependencies with `pip install -r requirements.txt`.
5. Run the notebooks in `data/generate/` to populate the tables.

## Tools

PostgreSQL, Python (pandas, SQLAlchemy, Faker), Jupyter, Power BI
