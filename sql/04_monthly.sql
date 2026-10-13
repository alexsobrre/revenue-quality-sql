CREATE OR REPLACE VIEW report_monthly AS
WITH monthly AS (
 SELECT cast(date_trunc('month',invoice_date) AS DATE) AS month,
        sum(gross_sales) AS gross_positive_sales,
        sum(negative_adjustment_value) AS negative_adjustments,
        sum(signed_value) AS net_recorded_sales,
        count(DISTINCT invoice_no) FILTER (WHERE line_class='positive_sale') AS positive_sale_invoices
 FROM eligible_lines GROUP BY 1
)
SELECT d.month,d.complete_observed_month,
       coalesce(m.gross_positive_sales,0) AS gross_positive_sales,
       coalesce(m.negative_adjustments,0) AS negative_adjustments,
       coalesce(m.net_recorded_sales,0) AS net_recorded_sales,
       coalesce(m.positive_sale_invoices,0) AS positive_sale_invoices,
       m.gross_positive_sales/nullif(m.positive_sale_invoices,0) AS average_positive_invoice_value,
       m.negative_adjustments/nullif(m.gross_positive_sales,0) AS adjustment_value_ratio
FROM dim_months d LEFT JOIN monthly m USING(month);

CREATE OR REPLACE VIEW report_growth_bridge AS
WITH lagged AS (
 SELECT *, lag(gross_positive_sales) OVER(ORDER BY month) AS prior_gross,
           lag(positive_sale_invoices) OVER(ORDER BY month) AS prior_orders,
           lag(average_positive_invoice_value) OVER(ORDER BY month) AS prior_aov,
           lag(net_recorded_sales) OVER(ORDER BY month) AS prior_net,
           avg(net_recorded_sales) OVER(ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3month_net
 FROM report_monthly WHERE complete_observed_month
)
SELECT *, gross_positive_sales-prior_gross AS gross_change,
       (positive_sale_invoices-prior_orders)*prior_aov AS order_volume_effect,
       positive_sale_invoices*(average_positive_invoice_value-prior_aov) AS invoice_value_effect,
       (net_recorded_sales-prior_net)/nullif(prior_net,0) AS net_monthly_growth
FROM lagged;
-- Sequential decomposition: quantity effect at prior AOV, then AOV at current volume.
-- This is an arithmetic attribution; it does not identify a causal growth driver.
