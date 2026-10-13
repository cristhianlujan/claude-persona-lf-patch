from __future__ import annotations
import unittest
from unittest.mock import patch
import lf_train_execution_recorder as r

def ctx():
    return dict(pr="2362",version="20261013010000",name="lf_example_v1",
                path="supabase/migrations/20261013010000_lf_example_v1.sql",
                source_blob="a"*40,source_sha256="b"*64,repo="o/r",
                head_sha="c"*40,persisted_head_sha="d"*40,run_id="100")

class ResumeEffectGuardTests(unittest.TestCase):
    def invoke(self, effect, ledger, receipt=None, allow_mark=False):
        calls=[]
        def fake(sql,**kwargs):
            calls.append(sql)
            if "fn_lf_operation_reserve_execution_v1" in sql:
                return {"status":"IN_PROGRESS","execution_id":r.identity("2362","20261013010000","100")["execution_id"]}
            if "lf_router_downstream_authority_validate_v1" in sql:
                return {"applicable":True,"valid":True,"code":"ROUTER_DOWNSTREAM_AUTHORITY_VALID","operation_code":"ACTUALIZACION_DB_LF"}
            if "fn_lf_operation_acquire_lease_v1" in sql:
                return {"result":"LEASE_ACQUIRED","lease_fence":2}
            if "v_lf_capability_entry_guard_v1" in sql:
                return {"entry_guard_state":"GUARDED","capability_code":"DB_WRITE_TRANSPORT"}
            if "fn_lf_operation_reserve_effect_v1" in sql:
                return effect
            if "fn_lf_operation_mark_effect_succeeded_v1" in sql:
                if allow_mark:
                    return {"result":"EFFECT_SUCCESS_PERSISTED"}
                self.fail("effect must not be marked on an unverified ledger")
            raise AssertionError(sql)
        with patch.object(r,"call",side_effect=fake),patch.object(r,"_effect_readback",return_value={"dispatch_key":r.identity("2362","20261013010000","100")["dispatch_key"]}),patch.object(r,"_record_step_if_needed",return_value={"status":r.CLEAN}),patch.object(r,"_ledger_readback",return_value=ledger):
            return r.begin(ctx())

    def _verified_close(self, *, ledger_sha=None, effect_state="SUCCEEDED",
                        receipt_name="lf_example_v1", parity="PASS", router_valid=True):
        state={"result":"TRAIN_EXECUTION_PATCH_RECORDED", "context":ctx(),
               "ids":{**r.identity("2362","20261013010000","100"),"lease_fence":"2"}}
        ledger={"version":ctx()["version"],"name":ctx()["name"],
                "source_sha256":ledger_sha or ctx()["source_sha256"]}
        effect={"state":effect_state,"dispatch_key":state["ids"]["dispatch_key"],
                "effect_request_sha256":ctx()["source_sha256"],
                "receipt":{"apply_receipt":{"ledger_version":ctx()["version"],
                                             "ledger_name":receipt_name}}}
        def authority(execution_id):
            if not router_valid:
                raise RuntimeError("TRAIN_EXEC_ROUTER_AUTHORITY_MISSING_OR_STALE")
        with patch.object(r,"_require_router_authority",side_effect=authority), \\
             patch.object(r,"_ledger_readback",return_value=ledger), \\
             patch.object(r,"_effect_readback",return_value=effect), \\
             patch.object(r,"_record_step_if_needed",return_value={"status":r.CLEAN}), \\
             patch.object(r,"call",return_value={"result":"EXECUTION_COMPLETED"}) as effect_call:
            result=r.close(state,"a"*40,parity)
            self.assertEqual(result["result"],"TRAIN_EXECUTION_COMPLETED")
            self.assertEqual(effect_call.call_count,1)

    def test_verified_close_works_without_replay(self):
        self._verified_close()

    def test_closure_blocks_wrong_ledger_digest(self):
        with self.assertRaisesRegex(RuntimeError,"CLOSE_EXACT_LEDGER_UNVERIFIED"):
            self._verified_close(ledger_sha="f"*64)

    def test_closure_blocks_unfinished_effect(self):
        with self.assertRaisesRegex(RuntimeError,"CLOSE_EFFECT_RECEIPT_UNVERIFIED"):
            self._verified_close(effect_state="RESERVED")

    def test_closure_blocks_receipt_mismatch(self):
        with self.assertRaisesRegex(RuntimeError,"CLOSE_EFFECT_RECEIPT_UNVERIFIED"):
            self._verified_close(receipt_name="other")

    def test_closure_blocks_stale_router(self):
        with self.assertRaisesRegex(RuntimeError,"ROUTER_AUTHORITY_MISSING_OR_STALE"):
            self._verified_close(router_valid=False)

    def test_closure_blocks_missing_parity(self):
        with self.assertRaisesRegex(RuntimeError,"CLOSE_STATE_MERGE_OR_PARITY_INVALID"):
            self._verified_close(parity="SKIPPED")

    def test_commit_rejects_forged_ledger(self):
        state={"result":"TRAIN_EXECUTION_READY_TO_APPLY","apply_required":True,
               "context":ctx(),"ids":{**r.identity("2362","20261013010000","100"),"lease_fence":"2"}}
        receipt={"status":"PASS","ledger_version":ctx()["version"],"ledger_name":ctx()["name"]}
        with patch.object(r,"_require_router_authority"), \\
             patch.object(r,"_ledger_readback",return_value={"version":ctx()["version"],"name":ctx()["name"],"source_sha256":"0"*64}), \\
             patch.object(r,"call") as mutation:
            with self.assertRaisesRegex(RuntimeError,"COMMIT_EXACT_LEDGER_UNVERIFIED"):
                r.commit(state,{"route":"TEST"},receipt)
            mutation.assert_not_called()

    def test_workflow_uses_resume_effect_decision_and_fatal_close(self):
        from pathlib import Path
        wf=(Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertIn("steps.train_exec.outputs.apply_required == 'true'",wf)
        self.assertIn("Enforce governed execution receipt before merge",wf)
        for marker in ("Router execution patch step (Train-managed, post-apply)",
                       "Router execution verify and close (Train-managed, post-merge)"):
            self.assertNotIn("continue-on-error: true",wf[wf.index(marker):wf.index(marker)+300])

    def test_verified_succeeded_effect_skips_apply_and_reuses_patch(self):
        receipt={"apply_receipt":{"ledger_version":"20261013010000","ledger_name":"lf_example_v1"}}
        effect={"result":"REPLAY_SUCCEEDED_EFFECT","receipt":receipt}
        ledger={"version":"20261013010000","name":"lf_example_v1","source_sha256":"b"*64}
        state=self.invoke(effect,ledger)
        self.assertFalse(state["apply_required"])
        self.assertEqual(state["resume"],"EFFECT_ALREADY_SUCCEEDED")

    def test_reserved_effect_with_exact_ledger_reconciles_without_apply(self):
        ledger={"version":"20261013010000","name":"lf_example_v1","source_sha256":"b"*64,
                "created_by":"SOURCE_FIRST"}
        state=self.invoke({"result":"RECONCILIATION_REQUIRED"},ledger,allow_mark=True)
        self.assertFalse(state["apply_required"])
        self.assertEqual(state["resume"],"LEDGER_EFFECT_RECONCILED")

    def test_already_applied_plan_reports_true_name_not_filename(self):
        from pathlib import Path
        wf=(Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertIn('echo "migration_name=$current_name" >> "$GITHUB_OUTPUT"',wf)
        self.assertNotIn('echo "migration_name=${target_path##*/}" >> "$GITHUB_OUTPUT"',wf)

    def test_first_effect_requires_apply_once(self):
        state=self.invoke({"result":"EFFECT_RESERVED_NEW"},{})
        self.assertTrue(state["apply_required"])

    def test_unresolved_reservation_without_ledger_does_not_replay(self):
        with self.assertRaisesRegex(RuntimeError,"RESERVED_WITHOUT_LEDGER_UNRESOLVED"):
            self.invoke({"result":"RECONCILIATION_REQUIRED"},{})

    def test_existing_ledger_wrong_source_does_not_mark_succeeded(self):
        with self.assertRaisesRegex(RuntimeError,"EXACT_SOURCE_MISMATCH"):
            self.invoke({"result":"RECONCILIATION_REQUIRED"},
                {"version":"20261013010000","name":"lf_example_v1","source_sha256":"0"*64})

    def test_success_receipt_with_different_ledger_cannot_skip(self):
        with self.assertRaisesRegex(RuntimeError,"SUCCEEDED_LEDGER_OR_RECEIPT_MISMATCH"):
            self.invoke({"result":"REPLAY_SUCCEEDED_EFFECT","receipt":{"apply_receipt":{"ledger_version":"20261013010000","ledger_name":"lf_example_v1"}}},
                        {"version":"20261013010000","name":"lf_example_v1","source_sha256":"f"*64})

if __name__=="__main__":
    unittest.main()
