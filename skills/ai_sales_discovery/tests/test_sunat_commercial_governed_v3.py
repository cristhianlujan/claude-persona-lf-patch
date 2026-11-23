import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))

import sunat_commercial_governed_v3 as v3
from sunat_batch_plan_v1 import sha,canonical


class GovernedCommercialWriter(unittest.TestCase):
    def setUp(self):
        self.rucs=["20000000001","20000000002"]
        self.exact=dict(source_sha256=["1"*64,"2"*64],
                        manifest_digest_sha256="3"*64)
        self.policy=dict(
            enabled=True,commercial_mode=True,
            commercial_run_ref=v3.RUN,
            old_manifest_replay_allowed=False,
            source_id=v3.SOURCE,
            rights_scope="SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20",
            reduced_rights_status="PERSISTENCIA_PERMITIDA",
            snapshot_sha256=self.exact["source_sha256"],
            original_manifest_digest_sha256=self.exact["manifest_digest_sha256"],
            historical_found_batches=136,
            expected_rows=2239,expected_batches=3,max_rows=1000,
            max_bytes=4194304,max_total_bytes=12_582_912,
            manifest_digest_sha256="4"*64,
            batch_digest_sha256="5"*64,
            existing_rucs_sha256=sha(canonical(self.rucs))
        )
        self.raw=dict(
            policy=self.policy,old_run="HOLD",old_batches=136,
            old_hist_rows=136000,operation="IN_PROGRESS",
            new_run=None,trigger_active=True,min_workers=50,
            existing_rucs=self.rucs
        )

    def test_valid_source_and_governed_roster(self):
        p,r=v3.validate_policy_and_roster(self.raw,self.exact)
        self.assertEqual(p,self.policy)
        self.assertEqual(r,set(self.rucs))
        candidate=dict(self.raw,operation=None,new_run=None)
        new_pol,new_roster=v3.validate_policy_and_roster(candidate,self.exact)
        self.assertEqual(new_roster,set(self.rucs))

    def test_reject_disabled_policy_old_run_or_new_run_drift(self):
        for change in (
            {"policy":dict(self.policy,enabled=False)},
            {"policy":dict(self.policy,commercial_mode=False)},
            {"policy":dict(self.policy,commercial_run_ref=v3.OLD)},
            {"old_run":"EN_EJECUCION"},
            {"old_batches":135},
            {"trigger_active":False},
            {"operation":"ABANDONED"},
            {"new_run":"HOLD"},
            {"min_workers":49}
        ):
            with self.subTest(change=change):
                with self.assertRaisesRegex(ValueError,"^COMMERCIAL_DB_POLICY_NOT_ADMITTED$"):
                    v3.validate_policy_and_roster(dict(self.raw,**change),self.exact)

    def test_reject_roster_tamper_or_duplicate(self):
        for roster in ([self.rucs[1],self.rucs[0]],
                       [self.rucs[0],self.rucs[0]],
                       ["BAD"],None):
            with self.subTest(roster=roster):
                with self.assertRaisesRegex(ValueError,"^COMMERCIAL_DB_ROSTER_CHANGED$"):
                    v3.validate_policy_and_roster(dict(self.raw,existing_rucs=roster),self.exact)

    def test_new_manifest_exact_and_no_runtime_authority_misclaim(self):
        r=dict(rows=2239,batches=3,total_bytes=3_500_000,
             manifest_digest_sha256="4"*64,batch_digest_sha256="5"*64,
             prior_existing_rucs_sha256=self.policy["existing_rucs_sha256"],
             historical_found_batches=136,
             scanned_remaining_rows=342657,
             excluded_by_commercial_policy=340390,
             skipped_already_registered=28,
             runtime_authorized=False,db_write_confirmed=False)
        # 340390+28+2239=342657
        self.assertEqual(v3.verify_manifest(r,self.policy)["rows"],2239)
        r["db_write_confirmed"]=True
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_VERIFIED_MANIFEST_MISMATCH$"):
            v3.verify_manifest(r,self.policy)
        r["db_write_confirmed"]=False
        r["manifest_digest_sha256"]="7"*64
        with self.assertRaisesRegex(ValueError,"^COMMERCIAL_VERIFIED_MANIFEST_MISMATCH$"):
            v3.verify_manifest(r,self.policy)

    def test_only_native_governed_operation_in_generated_sql(self):
        plan=[dict(batch_key="a"*64,ordinal=1,rows=1,bytes=2,
             capture_sha256=sha(b"[]"),consulta_evidencia_ref="https://example.com")]
        q=v3.plan_sql(plan,self.exact["source_sha256"])
        self.assertIn("fn_lf_operation_reserve_execution_v1",q)
        self.assertIn("saly.ventas_sunat_plan_prepare_v1",q)
        self.assertIn("fn_lf_operation_acquire_lease_v1",q)
        self.assertNotIn("INSERT INTO saly.ventas_hallazgos",q)
        payload=b"[]"
        b=v3.batch_sql(plan[0],payload,1,1)
        self.assertIn("saly.ventas_sunat_batch_execute_v1",b)
        self.assertIn("SUNAT_COMMERCIAL_BATCH_READBACK",b)
        self.assertNotIn("INSERT INTO saly.ventas_hallazgos",b)
        self.assertNotIn("DELETE FROM",b)

    def test_wrong_payload_cannot_be_written(self):
        entry=dict(batch_key="a"*64,ordinal=1,rows=1,bytes=2,
                   capture_sha256=sha(b"[]"))
        for payload in (b"[1]",b" "):
            with self.assertRaisesRegex(ValueError,"^COMMERCIAL_BATCH_SOURCE_DRIFT$"):
                v3.batch_sql(entry,payload,1,1)

    def test_final_readback_must_match(self):
        with patch.object(v3,"psql",return_value=dict(new_rows=2239,new_batches=3,
             ineligible=0,old_run="HOLD",total_sunat=7514)):
            r=v3.final_readback(2239,3)
            self.assertEqual(r["total_sunat"],7514)
        with patch.object(v3,"psql",return_value=dict(new_rows=2239,new_batches=3,
             ineligible=1,old_run="HOLD")):
            with self.assertRaisesRegex(ValueError,"SUNAT_COMMERCIAL_TERMINAL_READBACK_FAILED"):
                v3.final_readback(2239,3)


if __name__=="__main__":
    unittest.main()
