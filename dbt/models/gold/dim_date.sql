-- gold.dim_date: one row per day, 2020-01-01 to 2030-12-31.
-- Migrated from scripts/gold/sql/02_gold_dim_date.sql (logic unchanged).

SELECT
  date,
  year(date)                              AS year,
  quarter(date)                           AS quarter,
  month(date)                             AS month,
  date_format(date, 'yyyy-MM')            AS year_month,
  concat(year(date), '-Q', quarter(date)) AS year_quarter
FROM (
  SELECT explode(sequence(DATE'2020-01-01', DATE'2030-12-31', INTERVAL 1 DAY)) AS date
)
