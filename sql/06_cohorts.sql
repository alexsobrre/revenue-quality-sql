-- Cohorts are first OBSERVED positive purchase; do not claim first-ever acquisition.
-- One customer counts once per month, regardless of invoice count.
CREATE OR REPLACE VIEW report_cohort_retention AS
WITH purchase_months AS (
 SELECT DISTINCT customer_id,cast(date_trunc('month',invoice_date) AS DATE) AS activity_month
 FROM eligible_lines WHERE customer_id IS NOT NULL AND line_class='positive_sale'
), first_purchase AS (
 SELECT customer_id,min(activity_month) AS cohort_month FROM purchase_months GROUP BY customer_id
), sizes AS (
 SELECT cohort_month,count(*) AS cohort_customers FROM first_purchase GROUP BY cohort_month
), observed AS (
 SELECT f.cohort_month,p.activity_month,count(*) AS active_customers
 FROM purchase_months p JOIN first_purchase f USING(customer_id)
 GROUP BY f.cohort_month,p.activity_month
), eligible_periods AS (
 SELECT s.cohort_month,s.cohort_customers,d.month AS activity_month,
        date_diff('month',s.cohort_month,d.month) AS months_since_first_observed_purchase
 FROM sizes s JOIN dim_months d ON d.month>=s.cohort_month AND d.complete_observed_month
)
SELECT e.*,coalesce(o.active_customers,0) AS active_customers,
       coalesce(o.active_customers,0)::DOUBLE/e.cohort_customers AS monthly_repeat_rate
FROM eligible_periods e LEFT JOIN observed o USING(cohort_month,activity_month);

CREATE OR REPLACE VIEW report_cohort_summary AS
SELECT months_since_first_observed_purchase AS month_age,
       count(*) AS eligible_cohorts,sum(cohort_customers) AS eligible_customers,
       sum(active_customers) AS active_customers,
       sum(active_customers)::DOUBLE/sum(cohort_customers) AS weighted_monthly_repeat_rate
FROM report_cohort_retention GROUP BY 1;

CREATE OR REPLACE VIEW report_purchase_frequency AS
WITH purchases AS (
 SELECT customer_id,count(DISTINCT invoice_no) AS positive_purchase_invoices
 FROM eligible_lines WHERE customer_id IS NOT NULL AND line_class='positive_sale' GROUP BY customer_id
)
SELECT count(*) AS identified_purchasers,
       count(*) FILTER(WHERE positive_purchase_invoices>=2) AS purchasers_with_repeat_invoice,
       count(*) FILTER(WHERE positive_purchase_invoices>=2)::DOUBLE/count(*) AS observed_repeat_purchaser_share
FROM purchases;
