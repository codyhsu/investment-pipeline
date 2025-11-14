CREATE or REPLACE TABLE `portfolio.daily_holdings` AS(

WITH calendar AS (
  SELECT DATE_ADD(DATE '2022-11-01', INTERVAL day_offset DAY) AS calendar_date
  FROM UNNEST(GENERATE_ARRAY(0, DATE_DIFF(DATE '2025-11-01', DATE '2022-11-01', DAY))) AS day_offset
),
accumlative AS (
  SELECT
    c.calendar_date,
    te.ticker,
    SUM(IF(te.date <= c.calendar_date, te.quantity, 0)) AS daily_holding,
    SUM(IF(te.date <= c.calendar_date, te.amount_eu, 0)) AS invested_value
  FROM calendar c
  JOIN portfolio.transactions_enriched te ON te.date <= c.calendar_date
  GROUP BY c.calendar_date, te.ticker
),
joined AS (
  SELECT
    a.calendar_date,
    a.ticker,
    a.daily_holding,
    SAFE_DIVIDE(a.invested_value, a.daily_holding) AS avg_cost,
    me.price_eur AS market_price,
    a.invested_value,
    a.daily_holding * me.price_eur AS market_value
  FROM accumlative a
  LEFT JOIN portfolio.market_prices_enriched me
    ON a.calendar_date = me.date AND a.ticker = me.ticker
  WHERE me.price_eur IS NOT NULL
),
returns AS (
  SELECT
    *,
    market_value - invested_value AS unrealized_profit_eur,
    market_value - LAG(market_value) OVER (
      PARTITION BY ticker ORDER BY calendar_date
    ) AS daily_profit_eur,
    SAFE_DIVIDE(
      market_value,
      LAG(market_value) OVER (PARTITION BY ticker ORDER BY calendar_date)
    ) - 1 AS daily_return_pct  -- now in decimal format
  FROM joined
),
final AS (
  SELECT
    *,
    EXP(SUM(LN(1 + daily_return_pct)) OVER (
      PARTITION BY ticker ORDER BY calendar_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )) - 1 AS accumulated_return_pct  -- also in decimal format
  FROM returns
)

SELECT * FROM final
ORDER BY calendar_date, ticker)
