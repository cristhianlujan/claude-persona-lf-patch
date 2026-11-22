import csv
import hashlib
import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_company_v1 import MONTHLY_FIELDS, company, batches
from sunat_dual_stream_v1 import candidate_receipt

class TestDual(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.limits=dict(zip_bytes=100000,unpacked_bytes=100000,line_bytes=4000,archive_rows=50,ratio=500,
                         cohort_keys=20,spool_pages=200,max_source_rows=20,max_batch_rows=1,max_batch_bytes=8000,seconds=30)
        self.header=b'RUC|NOMBRE O RAZON SOCIAL|ESTADO DEL CONTRIBUYENTE|CONDICION DE DOMICILIO|UBIGEO|DOMICILIO|'
    def archive(self,name,header,body):
        p=self.root/(name+'.zip')
        with zipfile.ZipFile(p,'w',compression=zipfile.ZIP_DEFLATED) as z: z.writestr(name,header+b'\n'+body)
        return dict(path=str(p),zip_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),header_sha256=hashlib.sha256(header).hexdigest(),url='https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip' if name.endswith('.csv') else 'https://www2.sunat.gob.pe/padron_reducido_ruc.zip')
    def sources(self):
        out=io.StringIO(); w=csv.writer(out,lineterminator='\n')
        for key,geo in [(1,'150101'),(2,'110101'),(3,'170101'),(4,'150101'),(5,'110101'),(5,'110101')]:
            row=dict.fromkeys(MONTHLY_FIELDS,''); row.update(RUC=str(20000000000+key),UBIGEO=geo,NroTrab='NO DISPONIBLE'); w.writerow([row[k] for k in MONTHLY_FIELDS])
        m=self.archive('m.csv',','.join(MONTHLY_FIELDS).encode(),out.getvalue().encode())
        r=self.archive('r.txt',self.header,b'20000000001|EMPRESA A|ACTIVO|HABIDO|150101|CALLE PRIVADA|\n20000000002|COMPA\xd1IA|ACTIVO|HABIDO|170101|X|\n20000000003|FUERA|ACTIVO|HABIDO|170101|X|\n20000000004|VALIDA|ACTIVO|HABIDO|150101|X|\n20000000004|ROTA|ACTIVO\n20000000005|DUPLICADA|ACTIVO|HABIDO|110101|X|\n')
        return m,r
    def run_pair(self,m,r): return candidate_receipt(m,r,departments=['15','11'],limits=self.limits,directory=self.root)
    def test_join_scope_duplicates_quarantine_and_replay(self):
        m,r=self.sources(); receipt=self.run_pair(m,r)
        self.assertEqual(receipt,self.run_pair(m,r)); self.assertEqual((receipt['rows'],receipt['batches']),(2,2))
        self.assertEqual(receipt['stats']['reduced_quarantined'],1); self.assertFalse(receipt['db_write_confirmed'])
        self.assertFalse(receipt['runtime_authorized']); self.assertNotIn('CALLE',str(receipt)); self.assertEqual(len(list(self.root.iterdir())),2)
        records=[]
        for n,name,geo,redgeo in [(1,'EMPRESA A','150101','150101'),(2,'COMPAÑIA','110101','170101')]:
            month=dict.fromkeys(MONTHLY_FIELDS,''); month.update(RUC=str(20000000000+n),UBIGEO=geo,NroTrab='NO DISPONIBLE')
            red=dict(RUC=month['RUC'],nombre=name,estado='ACTIVO',condicion='HABIDO',ubigeo=redgeo)
            def evidence(src): return dict(url=src['url'],zip_sha256=src['zip_sha256'],header_sha256=src['header_sha256'],ordinal=n)
            records.append(company(month,red,evidence(m),evidence(r)))
        expected=hashlib.sha256(b''.join(hashlib.sha256(b).digest() for b in batches(records,1,8000))).hexdigest()
        self.assertEqual(receipt['batch_digest_sha256'],expected)
    def test_header_and_hash(self):
        m,r=self.sources(); r['header_sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'^HEADER_HASH$'): self.run_pair(m,r)
        m,r=self.sources(); m['zip_sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'^ZIP_HASH$'): self.run_pair(m,r)
    def test_terminal_crc(self):
        m,r=self.sources(); p=Path(r['path']); b=bytearray(p.read_bytes()); pos=b.index(b'PK\x01\x02'); b[pos+16]^=1; p.write_bytes(b); r['zip_sha256']=hashlib.sha256(b).hexdigest()
        with self.assertRaises(zipfile.BadZipFile): self.run_pair(m,r)
        self.assertEqual(len(list(self.root.iterdir())),2)
    def test_scope_and_quota(self):
        m,r=self.sources(); self.limits['cohort_keys']=1
        with self.assertRaisesRegex(ValueError,'^COHORT_LIMIT$'): self.run_pair(m,r)
        self.limits['cohort_keys']=20; self.limits['archive_rows']=2
        with self.assertRaisesRegex(ValueError,'^ARCHIVE_ROWS$'): self.run_pair(m,r)
        self.limits['archive_rows']=50; r['url']='https://evil.example/r.zip'
        with self.assertRaisesRegex(ValueError,'^SOURCE_URL$'): self.run_pair(m,r)

if __name__=='__main__': unittest.main()
