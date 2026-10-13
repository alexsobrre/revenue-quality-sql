CREATE OR REPLACE VIEW report_customer_concentration AS
WITH totals AS (
 SELECT customer_id,sum(gross_sales) AS gross_positive_sales,
        sum(negative_adjustment_value) AS negative_adjustments,sum(signed_value) AS net_recorded_sales,
        count(DISTINCT invoice_no) FILTER(WHERE line_class='positive_sale') AS purchase_invoices
 FROM eligible_lines WHERE customer_id IS NOT NULL GROUP BY customer_id
), ranked AS (
 SELECT *,row_number() OVER(ORDER BY gross_positive_sales DESC,customer_id) AS customer_rank,
        gross_positive_sales/sum(gross_positive_sales) OVER() AS identified_gross_share,
        sum(gross_positive_sales) OVER(ORDER BY gross_positive_sales DESC,customer_id ROWS UNBOUNDED PRECEDING)
        /sum(gross_positive_sales) OVER() AS cumulative_identified_gross_share
 FROM totals WHERE gross_positive_sales>0
)
SELECT * FROM ranked;

CREATE OR REPLACE VIEW report_concentration_summary AS
SELECT count(*) AS identified_purchasers,
       sum(identified_gross_share) FILTER(WHERE customer_rank<=10) AS top10_identified_gross_share,
       sum(identified_gross_share) FILTER(WHERE customer_rank<=ceil(identified_purchasers*.01)) AS top1pct_identified_gross_share
FROM report_customer_concentration, (SELECT count(*) AS identified_purchasers FROM report_customer_concentration);

CREATE OR REPLACE VIEW report_customer_country AS
SELECT country,sum(gross_sales) AS gross_positive_sales,
       sum(signed_value) AS net_recorded_sales,
       sum(negative_adjustment_value)/nullif(sum(gross_sales),0) AS adjustment_value_ratio,
       dense_rank() OVER(ORDER BY sum(signed_value) DESC) AS net_sales_rank
FROM eligible_lines GROUP BY country;
