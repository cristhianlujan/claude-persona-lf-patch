import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_company_v1 import MONTHLY_FIELDS, company
from sunat_batch_plan_v1 import canonical, sha
from sunat_commercial_delivery_v1 import commercial_payloads_from_verified

MONTHLY_URL="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip"
REDUCED_URL="https://www2.sunat.gob.pe/padron_reducido_ruc.zip"
PINS=["1"*64,"2"*64]


def pair(n,workers="50",em="ACTIVO",er="ACTIVO",cm="HABIDO",cr="HABIDO"):
    ruc=str(20000000000+n)
    monthly=dict.fromkeys(MONTHLY_FIELDS,"")
    monthly.update(RUC=ruc,Estado=em,Condicion=cm,UBIGEO="150101",NroTrab=workers)
    reduced=dict(RUC=ruc,nombre="Fixture "+str(n),estado=er,condicion=cr,ubigeo="150101")
    def proof(idx):
        return dict(url=MONTHLY_URL if idx==0 else REDUCED_URL,
                    zip_sha256=PINS[idx],header_sha256="f"*64,ordinal=n)
    return company(monthly,reduced,proof(0),proof(1))


class TestCommercialDelivery(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # Three immutable raw historical batches, first one already ingested
        # before the governed physical purge.
        rows=[[pair(1),pair(2)],
              [pair(3,workers="49"),pair(4,workers="50")],
              [pair(5,workers="80",cm="NO HABIDO"),pair(6,workers="80")]]
        self.entries=[]
        self.payloads=[]
        for idx,batch in enumerate(rows,1):
            payload=canonical(batch)
            digest=sha(payload)
            self.entries.append(dict(
                batch_key=sha(canonical(["PE-SUNAT-RUC",PINS,"LIMA_ICA",idx])),
                ordinal=idx,rows=len(batch),bytes=len(payload),
                capture_sha256=digest,
                consulta_evidencia_ref=MONTHLY_URL+"#captura-json-sha256="+digest
            ))
            self.payloads.append(payload)
        self.original_sha=sha(canonical(self.entries))
        self.opts=dict(original_manifest_sha256=self.original_sha,
                       snapshot_sha256=PINS,original_batches=3,
                       historical_found_batches=1,existing_rucs={"20000000006"},
                       min_workers=50,max_rows=2,max_bytes=20000,
                       max_batches=20,max_total_bytes=50000,
                       monthly_url=MONTHLY_URL,directory=self.tmp.name)

    def open(self,entries=None,payloads=None,**kw):
        options=dict(self.opts,**kw)
        return commercial_payloads_from_verified(
            iter(zip(entries or self.entries,payloads or self.payloads)),**options
        )

    def test_commercial_new_manifest_historical_skip_and_dedupe(self):
        with self.open() as (receipt,verified):
            p=list(verified)
            self.assertEqual(receipt["rows"],1)
            self.assertEqual(receipt["batches"],1)
            self.assertEqual(receipt["skipped_historical_rows"],2)
            self.assertEqual(receipt["scanned_remaining_rows"],4)
            self.assertEqual(receipt["excluded_by_commercial_policy"],2)
            self.assertEqual(receipt["skipped_already_registered"],1)
            self.assertNotEqual(receipt["manifest_digest_sha256"],self.original_sha)
            self.assertFalse(receipt["runtime_authorized"])
            self.assertFalse(receipt["db_write_confirmed"])
            self.assertEqual(receipt["manifest_digest_sha256"],sha(canonical(receipt["plan"])))
            self.assertEqual(p[0][0],receipt["plan"][0])
            self.assertEqual(p[0][0]["capture_sha256"],sha(p[0][1]))
            self.assertEqual(json.loads(p[0][1])[0]["capture"]["normalized"]["ruc"],
                             "20000000004")
        self.assertEqual(list(Path(self.tmp.name).iterdir()),[])

    def test_dual_source_or_workers_mismatch_rejected(self):
        with self.open(existing_rucs=set()) as (receipt,verified):
            self.assertEqual(receipt["rows"],2)
            self.assertEqual([item["capture"]["normalized"]["ruc"]
                for _,payload in verified for item in json.loads(payload)],
                ["20000000004","20000000006"])

    def test_policy_51_fails_closed_when_only_50_left(self):
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_NO_NEW_ELIGIBLE$"):
            with self.open(min_workers=81):
                self.fail("should not hand off empty or invalid manifest")
        self.assertEqual(list(Path(self.tmp.name).iterdir()),[])

    def test_changed_original_manifest_rejected(self):
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_PRIOR_MANIFEST_CHANGED$"):
            with self.open(original_manifest_sha256="f"*64):
                self.fail("tampered original manifest was released")
        self.assertEqual(list(Path(self.tmp.name).iterdir()),[])

    def test_tamper_ordinal_or_bytes_rejected(self):
        changed=[dict(x) for x in self.entries]
        changed[1]["ordinal"]=99
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_PRIOR_BATCH$"):
            with self.open(entries=changed):
                self.fail("bad ordinal")
        changed_payload=list(self.payloads)
        changed_payload[1]=b"x"+changed_payload[1]
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_PRIOR_BATCH$"):
            with self.open(payloads=changed_payload):
                self.fail("bad bytes")

    def test_source_pin_or_existing_roster_rejected(self):
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_PRIOR_BATCH$"):
            with self.open(snapshot_sha256=["a"*64,PINS[1]]):
                self.fail("bad pin")
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_EXISTING_ROSTER$"):
            with self.open(existing_rucs={"NOT_RUC"}):
                self.fail("invalid roster")

    def test_reject_nonpositive_parameters(self):
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_MIN_WORKERS$"):
            with self.open(min_workers=0):
                self.fail("zero threshold")
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_COMPLETED_PREFIX$"):
            with self.open(historical_found_batches=3):
                self.fail("old run complete")
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_LIMITS$"):
            with self.open(max_bytes=0):
                self.fail("unset quota")

    def test_cleanup_on_consumer_error(self):
        with self.assertRaisesRegex(RuntimeError,"caller"):
            with self.open() as (_,verified):
                next(verified)
                raise RuntimeError("caller")
        self.assertEqual(list(Path(self.tmp.name).iterdir()),[])


if __name__=="__main__":
    unittest.main()
