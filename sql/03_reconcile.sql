-- Credit notes cannot be linked to original invoices from these fields alone.
CREATE OR REPLACE VIEW report_reconciliation AS
SELECT sum(gross_sales) AS gross_positive_sales,
       coalesce(sum(negative_adjustment_value) FILTER (WHERE line_class='cancellation_adjustment'),0) AS cancellation_adjustments,
       coalesce(sum(negative_adjustment_value) FILTER (WHERE line_class='other_negative_adjustment'),0) AS other_negative_adjustments,
       sum(negative_adjustment_value) AS total_negative_adjustments,
       sum(signed_value) AS net_recorded_sales,
       sum(negative_adjustment_value)/nullif(sum(gross_sales),0) AS adjustment_value_ratio,
       sum(gross_sales) FILTER (WHERE customer_id IS NULL) / nullif(sum(gross_sales),0) AS unidentified_gross_share,
       sum(signed_value) FILTER (WHERE NOT product_like_code) AS net_non_product_code_value,
       count(DISTINCT invoice_no) FILTER (WHERE line_class='positive_sale') AS positive_sale_invoices,
       count(DISTINCT customer_id) FILTER (WHERE line_class='positive_sale') AS identified_purchasers
FROM eligible_lines;

CREATE OR REPLACE VIEW report_ledger_bridge AS
SELECT sum(signed_value) AS all_typed_recorded_value,
       sum(signed_value) FILTER (WHERE line_class IN ('positive_sale','cancellation_adjustment','other_negative_adjustment')) AS eligible_net_value,
       coalesce(sum(signed_value) FILTER (WHERE line_class NOT IN ('positive_sale','cancellation_adjustment','other_negative_adjustment')),0) AS excluded_typed_value,
       count(*) FILTER (WHERE signed_value IS NULL) AS unvalued_lines
FROM stg_lines;

CREATE OR REPLACE VIEW report_large_adjustments AS
SELECT source_row_id,invoice_no,stock_code,description,customer_id,invoice_date,
       negative_adjustment_value
FROM eligible_lines WHERE negative_adjustment_value>0
ORDER BY negative_adjustment_value DESC,source_row_id LIMIT 20;
