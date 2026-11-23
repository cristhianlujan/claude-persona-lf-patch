"""Static exact-source contract for approved SUNAT commercial activation."""
import hashlib
import json
import re
import unittest
from pathlib import Path

BASE=Path(__file__).resolve().parents[3]
NAME="lf_saly_sunat_commercial_run_activation_v3.sql"
matching=list((BASE/"supabase/migrations").glob("*_"+NAME))
PLAN=[
    dict(batch_key="8c2a94f82655df7c0f895e8dd68d52bbc21f4fb16ccd456218c52330650ecfd6",
         ordinal=1,rows=1000,bytes=1583328,
         capture_sha256="86809e0779078fcae37f191adf4731b38d0e9cefcc3928ef64de60861a0330ee",
         consulta_evidencia_ref="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip#captura-json-sha256=86809e0779078fcae37f191adf4731b38d0e9cefcc3928ef64de60861a0330ee"),
    dict(batch_key="258717c684fb076af3af6fd12279a9ab518af8fd01a2f5bdf1d9cfb102bcebbc",
         ordinal=2,rows=1000,bytes=1574852,
         capture_sha256="b6496aa54fc854679df1f58cd5126209ae056d157e857ebd0a89cdcc7909c464",
         consulta_evidencia_ref="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip#captura-json-sha256=b6496aa54fc854679df1f58cd5126209ae056d157e857ebd0a89cdcc7909c464"),
    dict(batch_key="3a83f7ebd89631e2581bdc9fd69af6364b805d6a031bf084f6bb084b70012049",
         ordinal=3,rows=239,bytes=372896,
         capture_sha256="2c1ccd0d754d403b273dd31572a0e209fd5c572d8680baa0e37f3c904b34b319",
         consulta_evidencia_ref="https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip#captura-json-sha256=2c1ccd0d754d403b273dd31572a0e209fd5c572d8680baa0e37f3c904b34b319")
]

def sha(obj):
    b=json.dumps(obj,sort_keys=True,ensure_ascii=False,separators=(",",":")).encode()
    return hashlib.sha256(b).hexdigest()

class CommercialActivation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if len(matching)!=1:
            raise AssertionError("exactly one commercial activation migration required")
        cls.s=matching[0].read_text()

    def test_source_sha_binds_all_three_pinned_batches(self):
        self.assertEqual(len(PLAN),3)
        self.assertEqual(sum(p["rows"] for p in PLAN),2239)
        self.assertEqual(sum(p["bytes"] for p in PLAN),3531076)
        digest=sha(PLAN)
        chain=hashlib.sha256(b"".join(bytes.fromhex(x["capture_sha256"]) for x in PLAN)).hexdigest()
        self.assertEqual(digest,"40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595")
        self.assertEqual(chain,"53857c092011a416c08cd924e48736d777c6e2d654bfb826ba5866c8a2e30256")
        self.assertIn(digest,self.s)
        self.assertIn(chain,self.s)

    def test_scope_admission_and_exact_roster(self):
        for required in (
            "SUNAT_COMMERCIAL_TRAIN_REQUIRED","SUNAT_COMMERCIAL_OLD_SOURCE_POLICY_DRIFT",
            "SUNAT_COMMERCIAL_MIN_WORKERS_DRIFT","SUNAT_COMMERCIAL_RUN_PRESTATE_DRIFT",
            "SUNAT_COMMERCIAL_HISTORICAL_ROWS_DRIFT","SUNAT_COMMERCIAL_EXISTING_ROSTER_DRIFT",
            "SUNAT_COMMERCIAL_ACTIVATION_READBACK_FAILED",
            "EXEC-SALY-SUNAT-PILOT-20261122-001",
            "EXEC-SALY-SUNAT-COMMERCIAL-20261123-001",
            "24dc6c6c9239e1b95a028a5148c42cc4a0047dea9d8660c5de877b25efa058a8",
            "v_roster<>5434","v_old_batches<>136","v_old_reported<>136000",
            "v_current_sunat<>5275","'expected_rows',2239",
            "'expected_batches',3","'commercial_source_duplicate_existing',28",
            "'enabled',true","'commercial_mode',true",
            "'old_manifest_replay_allowed',false","'max_total_bytes',4194304",
            "SUNAT_COMMERCIAL_MIN_WORKERS_V1"
        ):
            with self.subTest(required=required):
                self.assertIn(required,self.s)

    def test_only_policy_config_mutates_no_capture_data(self):
        upper=self.s.upper()
        self.assertEqual(len(re.findall(r"\bINSERT INTO\b",upper)),1)
        self.assertIn("INSERT INTO PUBLIC.LF_GLOBAL_CONFIG",upper)
        self.assertNotIn("DELETE FROM",upper)
        self.assertNotIn("TRUNCATE",upper)
        self.assertNotIn("UPDATE SALY.VENTAS_",upper)
        self.assertNotIn("INSERT INTO SALY.VENTAS_HALLAZGOS",upper)
        self.assertNotIn("GRANT EXECUTE",upper)
        self.assertIn("BEGIN;",upper)
        self.assertIn("COMMIT;",upper)

if __name__=="__main__":
    unittest.main()
