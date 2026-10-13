-- Run after 01–08; inspect actual timings, scans, filters, join, and aggregate.
-- Do not claim a speedup without a controlled before/after comparison.
EXPLAIN ANALYZE
SELECT p.latest_description,sum(e.signed_value) AS net_value
FROM eligible_lines e JOIN dim_products p USING(stock_code)
WHERE e.invoice_date>=TIMESTAMP '2011-01-01'
  AND e.invoice_date<TIMESTAMP '2011-12-01'
GROUP BY p.latest_description
ORDER BY net_value DESC LIMIT 10;
