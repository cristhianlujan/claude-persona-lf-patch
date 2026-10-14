"""Evidence-only R17 bundle rehearsal event. Do not grant runtime deployment."""
from pathlib import Path
import unittest

MIGRATIONS=Path(__file__).resolve().parents[3]/"supabase/migrations"
MATCHES=list(MIGRATIONS.glob("*_lf_ig_m105_r17_bundle_rehearsal_event_v1.sql"))
if len(MATCHES)!=1:
    raise RuntimeError("R17_OFFLINE_REHEARSAL_MIGRATION_MISSING_OR_AMBIGUOUS")
SQL=MATCHES[0].read_text()

def valid(s):
    required=[
        "c_type constant text := 'RUNTIME_PREFLIGHT'",
        "EPHEMERAL_FILE_BUNDLE_ONLY",
        "'acceptance_declared',false",
        "'provider_deployment_executed',false",
        "'provider_rollback_drill_executed',false",
        "'provider_idempotency_drill_executed',false",
        "'runtime_authorization_present',false",
        "'release_promoted',false",
        "'cp2_jobs_started',0",
        "'workflow_run_id',38524367551",
        "'source_commit','37a72b57966858d7dad7bd43fc84e7744d6c3f65'",
        "'rollback_commit','cbaecd8d154b593f7d16126e9f3097797f31a7aa'",
        "'repeated_forward_changes',0",
        "'repeated_rollback_changes',0",
        "a.write_allowed=false",
        "private.fn_lf_event_acceptance_signal_v2",
        "R17_FILE_RECEIPT_READBACK_FAILED",
    ]
    if not all(r in s for r in required):
        return False
    forbidden=[
        "UPDATE public.lf_router_action_registry",
        "UPDATE public.lf_operation_registry",
        "UPDATE public.lf_capability_current",
        "supabase functions deploy",
        "POST https://api.supabase.com",
    ]
    return not any(p in s for p in forbidden)

class ReceiptTests(unittest.TestCase):
    def test_exact_partial_receipt(self):
        self.assertTrue(valid(SQL))
    def test_no_forged_provider_deploy(self):
        self.assertFalse(valid(SQL.replace("'provider_deployment_executed',false","'provider_deployment_executed',true")))
    def test_no_forged_rollback(self):
        self.assertFalse(valid(SQL.replace("'provider_rollback_drill_executed',false","'provider_rollback_drill_executed',true")))
    def test_no_forged_effect_idempotency(self):
        self.assertFalse(valid(SQL.replace("'provider_idempotency_drill_executed',false","'provider_idempotency_drill_executed',true")))
    def test_no_forged_cp2(self):
        self.assertFalse(valid(SQL.replace("'cp2_jobs_started',0","'cp2_jobs_started',13")))
    def test_no_auto_authority(self):
        self.assertFalse(valid(SQL.replace("'runtime_authorization_present',false","'runtime_authorization_present',true")))
    def test_no_fake_replay(self):
        self.assertFalse(valid(SQL.replace("'repeated_forward_changes',0","'repeated_forward_changes',1")))
    def test_no_runtime_route_activation(self):
        self.assertFalse(valid(SQL+"UPDATE public.lf_router_action_registry SET write_allowed=true;"))

if __name__=="__main__":
    unittest.main()
