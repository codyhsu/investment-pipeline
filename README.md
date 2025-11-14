# 💼 Investment Portfolio Analytics Pipeline  
**End-to-End Workflow: Python → BigQuery → Looker**  
_Focus: SQL-driven analytics and financial data modeling_


## Overview  

This project demonstrates a **complete investment analytics workflow**, from data ingestion in **Google Colab** to SQL modeling in **BigQuery**, with results visualized in **Looker Studio**.  

The main objective is to compute **daily holdings, portfolio valuation, and PnL** using live market and FX data — focusing on **data modeling and SQL performance analytics** rather than front-end visualization.


## System Architecture  
<img src="001_project_structure.png" alt="Project Architecture" width="500"/>

**Data Source (Python / Colab)**  
- Read simulated monthly investment transactions  
- Fetch ETF and benchmark prices via `yfinance`  
- Download EUR/USD exchange rates from API  
- Upload clean datasets to **BigQuery Sandbox**

**ETL & Database (SQL / BigQuery)**  
- Calculate purchase quantity and daily positions  
- Compute market value, invested capital, PnL and returns (in EUR)  
- Aggregate holdings into a daily portfolio view  
- Optional: Join S&P 500 benchmark for performance comparison  

**Visualization (Looker Studio)**  
- KPI cards: Total Invested, Market Value, PnL, Return %  
- Time Series: Invested vs. Market Value vs. Benchmark  
*(Visualization is intentionally simple — the focus is on SQL modeling.)*


## Scenario: Investment Plan Assumptions  

- **Start date:** 1 Nov 2022 → 2 Sep 2025 (≈ 3 years)  
- **Monthly contribution:** €300  
- **Investment frequency:** 1st of each month  
- **Portfolio currency:** EUR (but using USD-denominated ETFs)

| Asset Class | Example ETF / Ticker | Allocation | Rationale |
|--------------|----------------------|-------------|------------|
| US Equities | **SPY** (S&P 500 ETF) | 40 % | Broad US market exposure |
| European Equities | **VGK** (Vanguard FTSE Europe ETF) | 20 % | Regional diversification |
| Global Bonds | **BNDX** (Intl. Bond ETF) | 20 % | Defensive stability |
| US Bonds | **IEF** (7–10 Yr Treasury ETF) | 15 % | Lower volatility core |
| Cash / Money Market | **SHV** (1–3 Month Treasury ETF) | 5 % | Liquidity buffer |


## Workflow Steps  

### **1️. Data Ingestion — Colab (Python)**  
- Load CSV (`investment_transactions_36_months.csv`)  
- Pull historical prices for all tickers via `yfinance`  
- Get daily EUR/USD FX rates  
- Upload clean tables to **BigQuery** using `pandas_gbq`  

**Skills:** Python ETL, data API integration, data cleaning, cloud upload.


### **2️. Data Modeling — BigQuery (SQL)**  
All analytics logic is implemented in SQL (focus of the project).  

Key tables created:  
| Table | Description |
|--------|-------------|
| `transactions_raw` | Uploaded from Colab (date, ticker, amount_eur) |
| `market_prices_eur` | USD prices converted to EUR using FX |
| `transactions_with_qty` | Quantity per purchase (based on purchase-day price) |
| `daily_holdings_basic` | Cumulative quantity, invested capital, market value, PnL |
| `portfolio_daily_agg` | Aggregated total portfolio + benchmark comparison |


### **3️. Visualization — Looker Studio (SQL-connected)**  
Simple dashboard with:  
- **KPI Cards:** Invested, Market Value, PnL, Return %  
- **Time Series:** Invested vs Market Value (step vs continuous)  
- **Optional:** Portfolio vs S&P 500 Benchmark  

*(Looker visuals kept simple to highlight the SQL backend.)*


## Results Summary (Oct 2025 snapshot)

| Metric | Definition | Result* |
|---------|-------------|----------|
| **Total Invested (EUR)** | Cumulative contributions | € 10,500.00 |
| **Current Market Value (EUR)** | Valuation as of Oct 2025 | € 13,037.92 |
| **Total PnL (EUR)** | Market Value − Invested | +€ 2,537.92 (+ 24.17 %) |
| **Benchmark (S&P 500 EUR)** | Return since Nov 2022 | + 57.3 % |
| **Investment CAGR (EUR)** | Market Value − Invested | 7.47 %|
| **Benchmark CAGR** | Return since Nov 2022 | + 16.28 % |
| **Portfolio vs Benchmark** | Relative performance | − 33.13 pp |
| **Best Performer** | |**SPY (+ 27.75 %)** |
| **Worst Performer** | | **IEF (+ 6.36 %)** |

\* Values illustrative; computed dynamically in BigQuery.


## Insights  
- Balanced allocation achieved **+ 6.9 % total return** with lower volatility than the S&P 500.  
- **Equities (SPY, VGK)** drove performance; bonds reduced drawdowns.  
- Demonstrates how **BigQuery SQL** can handle PnL, returns, and benchmark tracking at scale.  
- Modular design allows future expansion (risk metrics, automation, BI integration).


## Tech Stack  
| Layer | Tools |
|-------|--------|
| **Data Source & ETL** | Python (Colab), Pandas, yfinance, exchangerate.host API |
| **Data Warehouse** | Google BigQuery (Sandbox) |
| **Query Language** | SQL (Standard BigQuery SQL) |
| **Visualization** | Looker Studio (Google Data Studio) |

## Repository Structure  

```
investment-portfolio-pipeline/
├── README.md
├── data/
│   └── 002_investment_transactions_36_months.csv           # Sample transaction data (36 months)
│
├── notebooks/
│   └── 101_data_pipeline_colab.ipynb                    # Colab notebook for data ingestion & upload to BigQuery
│
├── sql/
│   ├── 201_portfolio_snapshot.sql                 # Total Performance
│   ├── 202_daily_holdings_basic.sql               # Daily portfolio valuation & PnL
│   ├── 203_market_prices_enriched.sql             # Market Price in EUR with daily changes
│
└── screenshots/
    ├── pipeline_architecture.png                       # Project architecture diagram (Colab → BigQuery → Looker)
    └── looker_sample_dashboard.png                     # Simple Looker dashboard preview
```
