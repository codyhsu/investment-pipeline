# Step-by-step Guide

This section outlines the reproducible workflow behind the investment portfolio pipeline.

🔁 End-to-End Flow: **Colab → BigQuery → Looker Studio**

**Why do I chooose this combination**

My goal is to build an end-to-end mini investment data pipeline, with

- live market API 
- transaction enrichment,
- cloud storage, and
- dashboard visualization  

So the key is to pick something that:

- Runs Python and SQL easily
- Connects to the cloud
- Doesn’t waste time on setup
- It's free

## How to use this template
- Replace placeholders (PROJECT_ID, GCP_DATASET, TABLE_NAME, GCS_BUCKET) with real values.
- Follow steps in order: Prereqs → Ingestion → Modeling → Validation → Visualize → Schedule.
- Keep small commits and document each change in the repo.

## 0. Prerequisites
- A Google Account, that's all you need!

## 1. Data Ingestion — Colab (Python)
**Objective**: read transactions CSV, pull prices & FX, and upload clean tables to BigQuery.

### 1.1 Set up 

- Go to colab.research.google.com
- New Notebook → “Investment Pipeline” (or any name you like)
- Upload **transactions.csv** to Google Drive
- Change the share setting permission to anyone with the link.

### 1.2 Notebook structure
notebook link:
- Section A: Config
- Section B: Load transactions CSV
- Section C: Fetch price history for selected tickers (yfinance)
- Section D: Restructure the table and keep only the date, ticker and close price
- Section D: Fetch EUR/USD FX rates
- Section F: Persist to BigQuery with pandas_gbq

### 1.2 Example code snippets (replace placeholders)

- Config
```python
PROJECT_ID = "PROJECT_ID"
DATASET = "GCP_DATASET"
TICKERS = ["SPY","VGK","BNDX","IEF","SHV"]
START_DATE = "2022-11-01"
END_DATE = "2025-09-30"
```

- Load transactions
```python
import pandas as pd
tx = pd.read_csv("data/002_investment_transactions_36_months.csv", parse_dates=["date"])
tx.head()
```

- Fetch prices (yfinance)
```python
import yfinance as yf
all_prices = []
for t in TICKERS:
    df = yf.download(t, start=START_DATE, end=END_DATE)
    df = df[["Adj Close"]].rename(columns={"Adj Close":"price_usd"})
    df["ticker"] = t
    df = df.reset_index().rename(columns={"Date":"date"})
    all_prices.append(df)
prices = pd.concat(all_prices, ignore_index=True)
```

- Fetch EUR/USD FX (example: exchangerate.host)
```python
import requests
fx = []
date = pd.to_datetime(START_DATE)
while date <= pd.to_datetime(END_DATE):
    iso = date.strftime("%Y-%m-%d")
    r = requests.get(f"https://api.exchangerate.host/{iso}?base=USD&symbols=EUR")
    rate = r.json()["rates"]["EUR"]
    fx.append({"date": iso, "usd_to_eur": rate})
    date += pd.Timedelta(days=1)
fx = pd.DataFrame(fx); fx["date"] = pd.to_datetime(fx["date"])
```

- Merge and compute price_eur
```python
prices = prices.merge(fx, on="date", how="left")
prices["price_eur"] = prices["price_usd"] * prices["usd_to_eur"]
# Optional: forward-fill fx if missing, or use business-day calendar
prices = prices.sort_values(["ticker", "date"]).ffill()
```

- Compute quantity on transaction dates and upload
```python
# join tx with price on date to compute qty_per_tx
tx_with_price = tx.merge(prices[["date","ticker","price_eur"]], on=["date","ticker"], how="left")
tx_with_price["quantity"] = tx_with_price["amount_eur"] / tx_with_price["price_eur"]

from pandas_gbq import to_gbq
to_gbq(tx_with_price, f"{DATASET}.transactions_with_qty", project_id=PROJECT_ID, if_exists="replace")
to_gbq(prices, f"{DATASET}.market_prices_eur", project_id=PROJECT_ID, if_exists="replace")
```

1.3 Expected outputs
- BigQuery tables:
  - GCP_DATASET.transactions_raw (optional)
  - GCP_DATASET.market_prices_eur
  - GCP_DATASET.transactions_with_qty


## 2. Data Modeling — BigQuery (SQL)
Objective: produce daily holdings, cumulative invested capital, market values, PnL, returns; store in tables for visualization.

2.1 Table creation order (run in this order)
- 201: market_prices_enriched.sql → GCP_DATASET.market_prices_eur (if additional enrichment needed)
- 202: transactions_with_qty.sql → ensure transaction qty and timestamps
- 203: daily_holdings_basic.sql → compute daily cumulative quantity per ticker + metrics
- 204: portfolio_daily_agg.sql → aggregate tickers into portfolio + benchmark comparison

2.2 Key SQL patterns

- Compute quantity per tx (if not computed in Python)
```sql
-- transactions_with_qty.sql
SELECT
  date,
  ticker,
  amount_eur,
  price_eur,
  SAFE_DIVIDE(amount_eur, price_eur) AS quantity
FROM
  `PROJECT_ID.GCP_DATASET.transactions_raw` t
JOIN
  `PROJECT_ID.GCP_DATASET.market_prices_eur` p USING (date, ticker)
```

- Build daily cumulative holdings (window)
```sql
-- daily_holdings_basic.sql
WITH dates AS (
  SELECT DISTINCT date FROM `PROJECT_ID.GCP_DATASET.market_prices_eur`
),
tx AS (
  SELECT date, ticker, quantity, amount_eur
  FROM `PROJECT_ID.GCP_DATASET.transactions_with_qty`
)
SELECT
  d.date,
  p.ticker,
  p.price_eur,
  COALESCE(SUM(t.quantity) OVER (PARTITION BY p.ticker ORDER BY d.date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) AS cumulative_qty,
  COALESCE(SUM(t.amount_eur) OVER (PARTITION BY p.ticker ORDER BY d.date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) AS invested_eur,
  (COALESCE(SUM(t.quantity) OVER (PARTITION BY p.ticker ORDER BY d.date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) * p.price_eur) AS market_value_eur,
  ( (COALESCE(SUM(t.quantity) OVER (PARTITION BY p.ticker ORDER BY d.date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) * p.price_eur) - COALESCE(SUM(t.amount_eur) OVER (PARTITION BY p.ticker ORDER BY d.date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) ) AS pnl_eur
FROM
  (SELECT date FROM dates) d
CROSS JOIN
  (SELECT DISTINCT ticker FROM `PROJECT_ID.GCP_DATASET.market_prices_eur`) tks
LEFT JOIN
  `PROJECT_ID.GCP_DATASET.market_prices_eur` p
  ON p.date = d.date AND p.ticker = tks.ticker
LEFT JOIN
  tx t
  ON t.date = d.date AND t.ticker = tks.ticker
ORDER BY d.date, p.ticker;
```

- Portfolio aggregate
```sql
-- portfolio_daily_agg.sql
SELECT
  date,
  SUM(invested_eur) AS total_invested_eur,
  SUM(market_value_eur) AS total_market_value_eur,
  SUM(pnl_eur) AS total_pnl_eur,
  SAFE_DIVIDE(SUM(market_value_eur) - SUM(invested_eur), NULLIF(SUM(invested_eur), 0)) AS total_return_pct
FROM
  `PROJECT_ID.GCP_DATASET.daily_holdings_basic`
GROUP BY date
ORDER BY date;
```

2.3 Materialization strategy
- For interactive development: use views to iterate quickly.
- For production: create scheduled queries to populate tables (WRITE_TRUNCATE daily).
- Partition daily tables by date to reduce cost and improve performance.


## 3. Visualization — Looker Studio
Objective: create dashboard KPIs and charts using BigQuery tables.

3.1 Connect BigQuery
- Add new data source → BigQuery → select PROJECT_ID → GCP_DATASET.portfolio_daily_agg (or view)
- Use credentials with proper access.

3.2 Recommended pages / widgets
- KPIs (most recent date):
  - Total Invested (EUR)
  - Current Market Value (EUR)
  - Total PnL (EUR)
  - Return % (market_value / invested - 1)
- Time series:
  - Invested vs Market Value: step (invested is stepwise) vs continuous market value
  - PnL over time
- Table / breakdown:
  - Per ticker: cumulative_qty, invested, market_value, pnl, return_pct
- Optional: Benchmark overlay (SP500) as separate time series field

3.3 Calculated fields (Looker Studio)
- Return % = (total_market_value_eur - total_invested_eur) / total_invested_eur
- Use the latest date using filter to show KPIs.


## 4. Validation & QA
Objective: ensure numbers are correct and consistent.

4.1 Quick checks (SQL)
- Reconcile total invested vs transactions:
```sql
SELECT SUM(amount_eur) AS sum_tx, (SELECT total_invested_eur FROM `PROJECT_ID.GCP_DATASET.portfolio_daily_agg` ORDER BY date DESC LIMIT 1) AS invested_latest
FROM `PROJECT_ID.GCP_DATASET.transactions_raw`;
```
- Check no missing prices on transaction dates:
```sql
SELECT t.date, t.ticker
FROM `PROJECT_ID.GCP_DATASET.transactions_raw` t
LEFT JOIN `PROJECT_ID.GCP_DATASET.market_prices_eur` p USING(date, ticker)
WHERE p.price_eur IS NULL;
```
- Spot-check quantities:
```sql
SELECT *
FROM `PROJECT_ID.GCP_DATASET.transactions_with_qty`
ORDER BY date DESC LIMIT 10;
```

4.2 Unit tests (suggested)
- Small test dataset with deterministic prices to run offline and assert expected holdings.
- Use CI to run a small SQL job that verifies invariant: latest_market_value = sum(ticker_market_value).

4.3 Common pitfalls
- Missing FX on weekends/holidays → use forward-fill or business day calendar.
- Timezones: ensure dates align (use DATE, not DATETIME).
- Rounding leading to tiny discrepancies — document rounding policy.


## 5. Scheduling & Automation
- Use BigQuery scheduled queries to refresh:
  - market_prices_enriched → daily
  - daily_holdings_basic → daily after prices
  - portfolio_daily_agg → daily after holdings
- Alternative: Cloud Composer / Cloud Functions trigger from notebook or scheduler.
- Use service account for scheduled queries and grant it BigQuery Data Editor on dataset.


## 6. Troubleshooting tips
- BigQuery API errors: ensure API enabled and billing (if not sandbox).
- Missing data after upload: check pandas_gbq if_exists parameter; use WRITE_TRUNCATE for reproducible state.
- Slow queries: partition by date and cluster by ticker; use approximate aggregation if necessary for large scale.


## 7. Release notes / change log
- Keep a CHANGELOG.md or release notes in repo. For each change record:
  - Date, files modified, reason, breaking changes (if any).


## 8. Checklist before sharing dashboard
- [ ] Verify latest date is correct and shows expected values
- [ ] Columns and units labeled (EUR)
- [ ] Data freshness documented (as-of date)
- [ ] Access permissions set for Looker Studio viewer
- [ ] Sanity checks completed (validation queries passed)


