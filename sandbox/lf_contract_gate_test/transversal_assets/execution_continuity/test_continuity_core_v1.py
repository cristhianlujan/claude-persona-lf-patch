#!/usr/bin/env python3
import unittest
from datetime import datetime, timezone
from continuity_core_v1 import decide, Mode, Verdict

def ctx(**overrides):
    base=dict(project="IG", operation_code="ACTUALIZACION_DB_LF", router_execution_id="EXEC-1",
        source_ref="git:blob", exact_identity="sha256:abc", owner_approval_ref="issue:1",
        currentness_receipt="registry:current", contract_ref="contract:v1", policy_ref="policy:v1",
        transport_ref="DB_WRITE_TRANSPORT", scope="SANDBOX", execution_authorized=True,
        dependencies_verified=True)
    base.update(overrides)
    return base

class CoreTest(unittest.TestCase):
    def test_no_router_blocks_every_mode(self):
        for mode in Mode:
            self.assertEqual(decide(mode,ctx(router_execution_id="")).verdict,Verdict.BLOCK)
    def test_wrong_project_scope_blocks(self):
        self.assertEqual(decide(Mode.RESUME,ctx(scope="PRODUCTION")).code,"PRODUCTION_NOT_AUTHORIZED")
    def test_recover_requires_rollback_and_original_blob(self):
        c=ctx(immutable_source_digest="sha", original_version="20261012010000",
          target_absent=True,compatibility_rollback_pass=True,conflict_scan_pass=True,
          replay_equivalent_absent=True,utc_now=datetime(2026,10,12,2,0,tzinfo=timezone.utc))
        self.assertEqual(decide(Mode.RECOVER,c).verdict,Verdict.ADMIT)
        self.assertEqual(decide(Mode.RECOVER,{**c,"replay_equivalent_absent":False}).verdict,Verdict.BLOCK)
        self.assertEqual(decide(Mode.RECOVER,{**c,"compatibility_rollback_pass":False}).verdict,Verdict.BLOCK)
        self.assertEqual(decide(Mode.RECOVER,{**c,"original_version":"20261013010000"}).code,"RECOVER_FUTURE_VERSION")
    def test_reconcile_never_writes_db_or_ledger(self):
        c=ctx(target_kind="GIT_ONLY",db_write=False,ledger_write=False,
              ledger_identity_readback=True,byte_identity_verified=True,rename_only_verified=True)
        self.assertEqual(decide(Mode.RECONCILE,c).verdict,Verdict.ADMIT)
        for change in (dict(db_write=True),dict(ledger_write=True),dict(target_kind="DB")):
            self.assertEqual(decide(Mode.RECONCILE,{**c,**change}).verdict,Verdict.BLOCK)
    def test_resume_never_replays_effect(self):
        c=ctx(checkpoint_verified=True,effect_guard_verified=True)
        self.assertEqual(decide(Mode.RESUME,{**c,"effect_state":"SUCCEEDED"}).verdict,Verdict.SKIP)
        self.assertEqual(decide(Mode.RESUME,{**c,"effect_state":"RESERVED"}).verdict,Verdict.BLOCK)
        self.assertEqual(decide(Mode.RESUME,{**c,"effect_state":"ABSENT","new_effect_reservation_authorized":True}).verdict,Verdict.ADMIT)
        self.assertEqual(decide(Mode.RESUME,{**c,"effect_state":"ABSENT"}).verdict,Verdict.BLOCK)

if __name__ == "__main__":
    unittest.main()
