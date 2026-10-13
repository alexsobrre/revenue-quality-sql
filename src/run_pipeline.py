"""Python transports source data; numbered SQL scripts own all business metrics."""
from pathlib import Path
import argparse, hashlib, json, urllib.request, zipfile, time
import duckdb
import pandas as pd
ROOT=Path(__file__).resolve().parents[1]
SOURCE_URL='https://archive.ics.uci.edu/static/public/352/online+retail.zip'
REPORTS=['quality','invoice_integrity','repeat_sensitivity','reconciliation','ledger_bridge','large_adjustments','monthly',
         'growth_bridge','customer_concentration','concentration_summary','customer_country',
         'cohort_retention','cohort_summary','purchase_frequency','products','product_watchlist','checks']

def prepare_folders():
    for folder in ['data/raw','data/processed','database','reports','figures','.vscode','.mplconfig','tests']:
        (ROOT/folder).mkdir(parents=True,exist_ok=True)

def acquire():
    prepare_folders()
    target=ROOT/'data/raw/Online Retail.xlsx'
    if not target.exists():
        archive=ROOT/'data/raw/online-retail.zip'
        urllib.request.urlretrieve(SOURCE_URL,archive)
        with zipfile.ZipFile(archive) as z:
            names=[x for x in z.namelist() if x.lower().endswith('.xlsx')]
            assert len(names)==1
            target.write_bytes(z.read(names[0]))
    return target

def run_pipeline():
    source=acquire()
    print('Reading original workbook...',flush=True)
    original=pd.read_excel(source,engine='openpyxl',dtype={'InvoiceNo':'string','StockCode':'string','Description':'string','Country':'string'})
    transport=pd.DataFrame({
        'source_row_id':range(1,len(original)+1),
        'invoice_no':original.InvoiceNo,
        'stock_code':original.StockCode,
        'description':original.Description,
        'quantity':original.Quantity.astype('string'),
        'invoice_date':original.InvoiceDate.astype('string'),
        'unit_price':original.UnitPrice.astype('string'),
        'customer_id':original.CustomerID.astype('Int64').astype('string').fillna(''),
        'country':original.Country})
    db=ROOT/'database/revenue_quality.duckdb'
    connection=duckdb.connect(str(db))
    connection.register('source_data',transport)
    connection.execute('CREATE OR REPLACE TABLE raw_lines AS SELECT * FROM source_data')
    timings=[]
    for path in sorted((ROOT/'sql').glob('0[1-8]_*.sql')):
        start=time.perf_counter()
        connection.execute(path.read_text())
        timings.append({'script':path.name,'seconds':time.perf_counter()-start})
        print('Executed',path.name,flush=True)
    for name in REPORTS:
        order={'monthly':'month','growth_bridge':'month','customer_concentration':'customer_rank',
               'cohort_retention':'cohort_month,months_since_first_observed_purchase',
               'cohort_summary':'month_age','products':'net_sales_rank,stock_code',
               'product_watchlist':'adjustment_value_ratio DESC,gross_positive_sales DESC'}.get(name)
        q=f'SELECT * FROM report_{name}'+(f' ORDER BY {order}' if order else '')
        connection.execute(q).df().to_csv(ROOT/f'reports/{name}.csv',index=False)
    checks=connection.execute('SELECT * FROM report_checks').df()
    assert checks.failures.eq(0).all(),checks
    plan=connection.execute("EXPLAIN ANALYZE SELECT p.latest_description,sum(e.signed_value) AS net_value FROM eligible_lines e JOIN dim_products p USING(stock_code) WHERE e.invoice_date>=TIMESTAMP '2011-01-01' AND e.invoice_date<TIMESTAMP '2011-12-01' GROUP BY p.latest_description ORDER BY net_value DESC LIMIT 10").fetchall()
    (ROOT/'reports/query_plan.txt').write_text('\n'.join(str(x[1]) for x in plan))
    pd.DataFrame(timings).to_csv(ROOT/'reports/pipeline_timings.csv',index=False)
    dates=connection.execute('SELECT min(invoice_date),max(invoice_date) FROM stg_lines').fetchone()
    manifest={'source_url':SOURCE_URL,'source_page':'https://archive.ics.uci.edu/dataset/352/online+retail',
              'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
              'source_rows':len(original),'first_timestamp':str(dates[0]),'last_timestamp':str(dates[1]),
              'retrieved_or_verified_utc':pd.Timestamp.now(tz='UTC').isoformat(),
              'duckdb_version':duckdb.__version__,
              'policy':'Preserve exact repeats in primary metrics; exclude nonpositive price/zero quantity and invalid fields; retain unknown customers in totals.'}
    (ROOT/'data/manifest.json').write_text(json.dumps(manifest,indent=2))
    connection.close()
    print('Pipeline complete. All reconciliation checks passed.',flush=True)
    return manifest

if __name__=='__main__': run_pipeline()
