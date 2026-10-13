-- Preserve raw records. SQL owns typing, flags, scope, and monetary arithmetic.
CREATE OR REPLACE TABLE stg_lines AS
WITH typed AS (
    SELECT source_row_id, trim(invoice_no) AS invoice_no,
           trim(stock_code) AS stock_code, description,
           try_cast(quantity AS INTEGER) AS quantity,
           try_cast(invoice_date AS TIMESTAMP) AS invoice_date,
           try_cast(unit_price AS DECIMAL(18,4)) AS unit_price,
           nullif(trim(customer_id),'') AS customer_id,
           nullif(trim(country),'') AS country
    FROM raw_lines
), flagged AS (
    SELECT *, upper(invoice_no) LIKE 'C%' AS cancellation_invoice,
           regexp_full_match(stock_code,'[0-9]{5}[A-Za-z]?') AS product_like_code,
           row_number() OVER (
               PARTITION BY invoice_no, stock_code, description, quantity,
                            invoice_date, unit_price, customer_id, country
               ORDER BY source_row_id
           ) AS exact_repeat_number,
           cast(quantity * unit_price AS DECIMAL(22,4)) AS signed_value
    FROM typed
)
SELECT *, CASE
    WHEN invoice_date IS NULL OR invoice_no IS NULL OR invoice_no = ''
         OR stock_code IS NULL OR stock_code = '' OR quantity IS NULL
         OR unit_price IS NULL THEN 'invalid_required_field'
    WHEN unit_price < 0 THEN 'negative_price'
    WHEN unit_price = 0 OR quantity = 0 THEN 'zero_value'
    WHEN cancellation_invoice AND quantity > 0 THEN 'cancellation_positive_quantity'
    WHEN quantity < 0 AND cancellation_invoice THEN 'cancellation_adjustment'
    WHEN quantity < 0 THEN 'other_negative_adjustment'
    ELSE 'positive_sale'
END AS line_class
FROM flagged;

CREATE OR REPLACE TABLE dim_customers AS
SELECT DISTINCT customer_id FROM stg_lines WHERE customer_id IS NOT NULL;

CREATE OR REPLACE TABLE dim_products AS
SELECT stock_code,
       arg_max(description, invoice_date) FILTER (WHERE description IS NOT NULL) AS latest_description,
       bool_or(product_like_code) AS product_like_code
FROM stg_lines GROUP BY stock_code;

CREATE OR REPLACE TABLE dim_invoices AS
SELECT invoice_no, min(invoice_date) AS first_line_time,
       count(*) AS line_count, count(DISTINCT customer_id) AS identified_customer_count,
       count(DISTINCT country) AS country_count,
       count(DISTINCT cast(invoice_date AS DATE)) AS date_count
FROM stg_lines GROUP BY invoice_no;

CREATE OR REPLACE TABLE fact_lines AS
SELECT * FROM stg_lines;

CREATE OR REPLACE VIEW eligible_lines AS
SELECT *, CASE WHEN line_class='positive_sale' THEN signed_value ELSE 0 END AS gross_sales,
          CASE WHEN line_class IN ('cancellation_adjustment','other_negative_adjustment')
               THEN -signed_value ELSE 0 END AS negative_adjustment_value
FROM fact_lines
WHERE line_class IN ('positive_sale','cancellation_adjustment','other_negative_adjustment');

CREATE OR REPLACE TABLE dim_months AS
WITH bounds AS (
 SELECT date_trunc('month',min(invoice_date)) AS first_month,
        date_trunc('month',max(invoice_date)) AS final_observed_month
 FROM stg_lines
)
SELECT cast(month AS DATE) AS month,
       month < final_observed_month AS complete_observed_month
FROM bounds, generate_series(first_month,final_observed_month,INTERVAL 1 MONTH) t(month);
