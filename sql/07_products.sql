-- Product-like code syntax is a scope proxy, not a verified product taxonomy.
CREATE OR REPLACE VIEW report_products AS
WITH aggregated AS (
 SELECT stock_code,sum(gross_sales) AS gross_positive_sales,
        sum(negative_adjustment_value) AS negative_adjustments,sum(signed_value) AS net_recorded_sales,
        count(DISTINCT invoice_no) FILTER(WHERE line_class='positive_sale') AS purchase_invoices,
        count(DISTINCT invoice_no) FILTER(WHERE line_class!='positive_sale') AS adjustment_invoices
 FROM eligible_lines WHERE product_like_code GROUP BY stock_code
)
SELECT a.*,p.latest_description,
       negative_adjustments/nullif(gross_positive_sales,0) AS adjustment_value_ratio,
       dense_rank() OVER(ORDER BY net_recorded_sales DESC) AS net_sales_rank
FROM aggregated a JOIN dim_products p USING(stock_code);

CREATE OR REPLACE VIEW report_product_watchlist AS
SELECT * FROM report_products
WHERE gross_positive_sales>=10000 AND purchase_invoices>=20
ORDER BY adjustment_value_ratio DESC,gross_positive_sales DESC;
-- Thresholds are declared investigation filters, not optimized business cutoffs.
