-- Do not silently delete exact repeated lines or customers with unknown IDs.
CREATE OR REPLACE VIEW report_quality AS
SELECT line_class, count(*) AS line_count,
       sum(signed_value) AS recorded_signed_value,
       count(*) FILTER (WHERE customer_id IS NULL) AS unidentified_lines,
       count(*) FILTER (WHERE exact_repeat_number > 1) AS exact_repeat_lines,
       count(*) FILTER (WHERE NOT product_like_code) AS non_product_code_lines
FROM stg_lines GROUP BY line_class;

CREATE OR REPLACE VIEW report_invoice_integrity AS
SELECT count(*) AS invoices,
       count(*) FILTER (WHERE identified_customer_count > 1) AS invoices_with_multiple_customer_ids,
       count(*) FILTER (WHERE country_count > 1) AS invoices_with_multiple_countries,
       count(*) FILTER (WHERE date_count > 1) AS invoices_on_multiple_dates
FROM dim_invoices;

CREATE OR REPLACE VIEW report_repeat_sensitivity AS
SELECT 'Preserve all recorded lines (primary)' AS treatment,
       count(*) AS eligible_lines, sum(signed_value) AS net_recorded_sales
FROM eligible_lines
UNION ALL
SELECT 'Keep first exact repeat only (sensitivity)', count(*),sum(signed_value)
FROM eligible_lines WHERE exact_repeat_number=1;
