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
    def invoke(self, effect, ledger, receipt=None):
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
                self.fail("effect must not be marked on an unverified ledger")
            raise AssertionError(sql)
        with patch.object(r,"call",side_effect=fake),patch.object(r,"_effect_readback",return_value={"dispatch_key":r.identity("2362","20261013010000","100")["dispatch_key"]}),patch.object(r,"_record_step_if_needed",return_value={"status":r.CLEAN}),patch.object(r,"_ledger_readback",return_value=ledger):
            return r.begin(ctx())

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
