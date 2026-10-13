-- Zero means the stated integrity condition passed. Checks do not drive metrics.
CREATE OR REPLACE VIEW report_checks AS
SELECT 'Gross minus adjustments equals net' AS check_name,
       CASE WHEN abs(gross_positive_sales-total_negative_adjustments-net_recorded_sales)<0.0001 THEN 0 ELSE 1 END AS failures
FROM report_reconciliation
UNION ALL
SELECT 'Typed source bridge balances',
       CASE WHEN abs(all_typed_recorded_value-eligible_net_value-excluded_typed_value)<0.0001 THEN 0 ELSE 1 END
FROM report_ledger_bridge
UNION ALL
SELECT 'Monthly net equals eligible ledger',
       CASE WHEN abs((SELECT sum(net_recorded_sales) FROM report_monthly)-(SELECT sum(signed_value) FROM eligible_lines))<0.0001 THEN 0 ELSE 1 END
UNION ALL
SELECT 'Growth decomposition balances',count(*)
FROM report_growth_bridge
WHERE prior_gross IS NOT NULL AND abs(gross_change-order_volume_effect-invoice_value_effect)>0.0001
UNION ALL
SELECT 'Cohort rate is between zero and one',count(*)
FROM report_cohort_retention WHERE monthly_repeat_rate<0 OR monthly_repeat_rate>1
UNION ALL
SELECT 'Invoice dimension is unique',count(*)-count(DISTINCT invoice_no) FROM dim_invoices
UNION ALL
SELECT 'Product dimension is unique',count(*)-count(DISTINCT stock_code) FROM dim_products
UNION ALL
SELECT 'Line ID is unique',count(*)-count(DISTINCT source_row_id) FROM fact_lines
UNION ALL
SELECT 'Product join preserves eligible row count',
       CASE WHEN (SELECT count(*) FROM eligible_lines JOIN dim_products USING(stock_code))=(SELECT count(*) FROM eligible_lines) THEN 0 ELSE 1 END;
