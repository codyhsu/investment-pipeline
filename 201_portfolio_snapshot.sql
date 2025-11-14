CREATE OR REPLACE TABLE portfolio.portfolio_snapshot AS
WITH
aggregated_transactions AS (
  SELECT
    ticker,
    SUM(quantity) AS total_units_held,
    SUM(amount_eu) AS cost_basis_eur
  FROM
    portfolio.transactions_enriched
  GROUP BY
    ticker
),
market_valuation AS (
  SELECT
    m.date AS valuation_date,
    m.ticker,
    m.price_usd,
    (m.price_usd / f.EUR_USD_rate) AS unit_price_eur
  FROM
    portfolio.market_prices m
  JOIN
    portfolio.fx_rates f
  USING (date)
  WHERE m.date = (
    SELECT MAX(date)
    FROM portfolio.market_prices
  )
)

SELECT
  t.ticker,
  v.valuation_date,
  t.total_units_held,
  t.cost_basis_eur AS cost_basis_eur,
  v.unit_price_eur AS unit_price_eur,
  v.unit_price_eur * t.total_units_held AS market_value_eur,
  (v.unit_price_eur * t.total_units_held) - t.cost_basis_eur AS unrealized_gain_eur,
  ((v.unit_price_eur * t.total_units_held) / t.cost_basis_eur - 1) * 100 AS performance_pct
FROM
  aggregated_transactions t
JOIN
  market_valuation v
ON
  t.ticker = v.ticker;
