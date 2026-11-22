import hashlib
import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_company_v1 import company, MONTHLY_FIELDS
from sunat_join_batches_v1 import joined_batches
from sunat_batch_plan_v1 import canonical, sha, plan_verified_batches
M='https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip'
R='https://www2.sunat.gob.pe/padron_reducido_ruc.zip'
S=['a'*64,'b'*64]

def row(n,geo='150101',source=None):
    ruc=str(20000000000+n)
    m=dict.fromkeys(MONTHLY_FIELDS,''); m.update(RUC=ruc,UBIGEO=geo,NroTrab='NO DISPONIBLE')
    r=dict(RUC=ruc,nombre='FIXTURE',estado='',condicion='',ubigeo=geo)
    e=dict(url=M,zip_sha256=S[0],header_sha256='d'*64,ordinal=n)
    return company(m,r,e,dict(e,url=R,zip_sha256=source or S[1]))

class TestPlan(unittest.TestCase):
    def setUp(self):
        self.payloads=[canonical([row(1)]),canonical([row(2)])]
        self.expected=dict(state='CANDIDATE_READ_ONLY',source_id='PE-SUNAT-RUC',qa_baseline_match=True,runtime_authorized=False,db_write_confirmed=False,source_sha256=S,scope=['11','15'],rows=2,batches=2,batch_digest_sha256=hashlib.sha256(b''.join(hashlib.sha256(p).digest() for p in self.payloads)).hexdigest())
        self.limits=dict(max_rows=1,max_bytes=4096,max_batches=2,max_total_bytes=8192)
    def run_plan(self,p=None): return plan_verified_batches(self.payloads if p is None else p,expected=self.expected,monthly_url=M,scope_key='LIMA_ICA',limits=self.limits)
    def test_positive_replay(self):
        p=self.run_plan();self.assertEqual(p,self.run_plan());self.assertEqual(p['rows'],2);self.assertEqual(len(p['plan']),2);self.assertNotEqual(p['plan'][0]['batch_key'],p['plan'][1]['batch_key']);self.assertEqual(p['plan'][0]['consulta_evidencia_ref'],M+'#captura-json-sha256='+sha(self.payloads[0]));self.assertNotIn('FIXTURE',str(p));self.assertFalse(p['db_write_confirmed'])
    def test_duplicate(self):
        with self.assertRaisesRegex(ValueError,'^RUC_ORDER_DUPLICATE$'): self.run_plan([self.payloads[0]]*2)
    def test_drift(self):
        with self.assertRaisesRegex(ValueError,'^TERMINAL_RECONCILIATION$'): self.run_plan(self.payloads[:1])
    def test_source(self):
        with self.assertRaisesRegex(ValueError,'^SNAPSHOT_MISMATCH$'): self.run_plan([canonical([row(1,source='c'*64)])])
    def test_quota(self):
        self.limits['max_total_bytes']=1
        with self.assertRaisesRegex(ValueError,'^TOTAL_BYTES$'): self.run_plan()
    def test_unauthorized_mode(self):
        self.expected['runtime_authorized']=True
        with self.assertRaisesRegex(ValueError,'^RECEIPT_BOUNDARY$'): self.run_plan()
    def test_scope(self):
        with self.assertRaisesRegex(ValueError,'^SCOPE_ROW$'): self.run_plan([canonical([row(1,geo='170101')])])
    def test_real_join_stream(self):
        def source(kind):
            for n in (2,1):
                ob=row(n)['capture']['observations'][kind]
                yield ob['raw'],ob['evidence']
        stream=joined_batches(source('monthly'),source('reduced'),spool_pages=100,max_source_rows=20,max_batch_rows=1,max_batch_bytes=4096)
        self.assertEqual(self.run_plan(stream),self.run_plan())
    def test_capture_contract(self):
        r=row(1); r['capture']['normalized']['razon_social']='WRONG';r['capture_sha256']=sha(canonical(r['capture']))
        with self.assertRaisesRegex(ValueError,'^CAPTURE_CONTRACT$'): self.run_plan([canonical([r])])
    def test_canonical(self):
        with self.assertRaisesRegex(ValueError,'^BATCH_SHAPE_OR_CANONICAL$'): self.run_plan([self.payloads[0]+b' '])
if __name__=='__main__': unittest.main()
