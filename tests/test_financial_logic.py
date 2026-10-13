import unittest
from pathlib import Path
import duckdb,pandas as pd
ROOT=Path(__file__).resolve().parents[1]

class FinancialLogic(unittest.TestCase):
    def setUp(self):
        self.db=duckdb.connect(':memory:')
        records=[
          ('1','10001','Item',2,'2020-01-05',10,'10','UK'),
          ('1','10001','Item',2,'2020-01-05',10,'10','UK'),
          ('C2','10001','Item',-1,'2020-01-06',10,'10','UK'),
          ('3','10001','Item',-1,'2020-01-07',5,'10','UK'),
          ('4','10001','Item',2,'2020-01-08',0,'','UK'),
          ('5','10001','Item',1,'2020-01-09',-2,'10','UK'),
          ('6','10001','Item',0,'2020-03-03',5,'10','UK'),
          ('C7','10001','Item',1,'2020-01-11',10,'10','UK'),
          ('9','10001','Item',1,'2020-02-05',20,'','UK')]
        frame=pd.DataFrame(records,columns=['invoice_no','stock_code','description','quantity','invoice_date','unit_price','customer_id','country'])
        frame.insert(0,'source_row_id',range(1,len(frame)+1))
        self.db.register('fixture',frame)
        self.db.execute('CREATE TABLE raw_lines AS SELECT * FROM fixture')
        for p in sorted((ROOT/'sql').glob('0[1-8]_*.sql')): self.db.execute(p.read_text())
    def tearDown(self): self.db.close()
    def test_signs_scope_and_unknown_customers(self):
        row=self.db.execute('SELECT gross_positive_sales,total_negative_adjustments,net_recorded_sales,unidentified_gross_share FROM report_reconciliation').fetchone()
        self.assertEqual(float(row[0]),60)
        self.assertEqual(float(row[1]),15)
        self.assertEqual(float(row[2]),45)
        self.assertAlmostEqual(row[3],1/3)
        self.assertEqual(self.db.execute('SELECT sum(failures) FROM report_checks').fetchone()[0],0)
    def test_exact_repeats_preserved_and_sensitivity_disclosed(self):
        values=self.db.execute('SELECT net_recorded_sales FROM report_repeat_sensitivity ORDER BY treatment DESC').fetchall()
        self.assertEqual(sorted(float(x[0]) for x in values),[25,45])
    def test_zero_activity_month_is_not_missing_and_future_month_is_excluded(self):
        age1=self.db.execute('SELECT active_customers,monthly_repeat_rate FROM report_cohort_retention WHERE months_since_first_observed_purchase=1').fetchone()
        self.assertEqual(age1,(0,0.0))
        self.assertEqual(self.db.execute("SELECT count(*) FROM report_cohort_retention WHERE activity_month=DATE '2020-03-01'").fetchone()[0],0)

if __name__=='__main__': unittest.main()
