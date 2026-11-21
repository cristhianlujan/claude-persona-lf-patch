import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_history_v1 import evaluate


class TestHistory(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.ruc = "20000000001"
        self.missing = "20000000002"
        self.snapshots = []
        for period,ubigeo in [("2026-10","150101"),("2023-10","040101")]:
            path=Path(tmp.name)/(period+".zip")
            with ZipFile(path,"w") as z:
                z.writestr("padron.csv",f"RUC,UBIGEO\n{self.ruc},{ubigeo}\n{self.ruc},{ubigeo}\n")
            self.snapshots.append(dict(period=period,path=str(path),url="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_"+period.replace("-","")+".zip",
                  sha256=hashlib.sha256(path.read_bytes()).hexdigest(),header_sha256=hashlib.sha256(b"RUC,UBIGEO").hexdigest()))
        self.request=dict(as_of="2026-11-21",rucs=[self.ruc,self.missing],snapshots=self.snapshots,
                          limits=dict(zip_bytes=3000,unpacked_bytes=1000,line_bytes=400,rows_per_archive=20,cohort_size=2,snapshots=5))

    def test_geographic_move_gap_duplicates_missing(self):
        first,missing=evaluate(self.request)["records"]
        self.assertEqual((first["first_seen_period"],first["ordinal"],first["min_full_months"]),("2023-10",1,36))
        self.assertIsNone(missing["min_full_months"])

    def test_legacy_label_with_quoted_comma(self):
        source = self.snapshots[1]
        path = Path(source["path"])
        with ZipFile(path,"w") as z:
            z.writestr("monthly.csv",b'RUC,UBIGEO\n'+self.ruc.encode()+b',"PE\xd1A, SECTOR"\n')
        source["sha256"]=hashlib.sha256(path.read_bytes()).hexdigest()
        self.assertEqual(evaluate(self.request)["records"][0]["min_full_months"],36)

    def test_boundary(self):
        self.request.update(as_of="2026-10-01",snapshots=[self.snapshots[1]])
        self.assertEqual(evaluate(self.request)["records"][0]["min_full_months"],35)

    def test_bad_hash_and_unclosed_period(self):
        self.snapshots[0]["sha256"]="0"*64
        with self.assertRaisesRegex(ValueError,"^ZIP_HASH$"):
            evaluate(self.request)
        self.request["as_of"]="2026-10-01"
        with self.assertRaisesRegex(ValueError,"^UNCLOSED_PERIOD$"):
            evaluate(self.request)

    def test_relabelled_source(self):
        self.snapshots.append(dict(self.snapshots[1],period="2024-10",url=self.snapshots[1]["url"].replace("202310","202410")))
        with self.assertRaisesRegex(ValueError,"^DUPLICATE_SNAPSHOT$"):
            evaluate(self.request)


if __name__=="__main__":
    unittest.main()
