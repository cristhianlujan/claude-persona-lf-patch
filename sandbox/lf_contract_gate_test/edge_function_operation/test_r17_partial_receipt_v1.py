"""R17 factual event receipt must never pretend runtime deploy or accept CP2."""
from pathlib import Path
import unittest

MIGRATIONS = Path(__file__).resolve().parents[3] / "supabase/migrations"
MATCHES = list(MIGRATIONS.glob("*_lf_ig_m105_r17_read_evidence_event_v1.sql"))
if len(MATCHES) != 1:
    raise RuntimeError("R17_READ_EVENT_MIGRATION_MISSING_OR_AMBIGUOUS")
SQL = MATCHES[0].read_text()

def conforms(s):
    required=(
        "c_event_type constant text := 'RUNTIME_PREFLIGHT'",
        "'operational-event/v2'",
        "'acceptance_declared',false",
        "'provider_deployment_executed',false",
        "'runtime_rollback_drill_executed',false",
        "'effect_idempotency_drill_executed',false",
        "'runtime_authorization_present',false",
        "'release_promoted',false",
        "'cp2_jobs_started',0",
        "route.write_allowed=false",
        "private.fn_lf_event_acceptance_signal_v2",
        "'p50_ms',107.307",
        "'p90_ms',154.684",
        "'max_ms',154.684",
        "'github_run_id',38520767968",
        "R17_PARTIAL_EVENT_READBACK_FAILED",
    )
    if any(x not in s for x in required):return False
    if "UPDATE public.lf_operation_registry" in s or "UPDATE public.lf_router_action_registry" in s:
        return False
    return True

class PartialR17ReceiptTests(unittest.TestCase):
    def test_factual_receipt_exact(self):
        self.assertTrue(conforms(SQL))
    def test_no_forged_acceptance(self):
        self.assertFalse(conforms(SQL.replace("'acceptance_declared',false","'acceptance_declared',true")))
    def test_no_forged_runtime_rollback(self):
        self.assertFalse(conforms(SQL.replace("'runtime_rollback_drill_executed',false","'runtime_rollback_drill_executed',true")))
    def test_no_forged_idempotency(self):
        self.assertFalse(conforms(SQL.replace("'effect_idempotency_drill_executed',false","'effect_idempotency_drill_executed',true")))
    def test_no_forged_cp2_runs(self):
        self.assertFalse(conforms(SQL.replace("'cp2_jobs_started',0","'cp2_jobs_started',13")))
    def test_no_missing_artifact(self):
        self.assertFalse(conforms(SQL.replace("'github_run_id',38520767968","'github_run_id',0")))
    def test_no_route_activation(self):
        self.assertFalse(conforms(SQL.replace("route.write_allowed=false","route.write_allowed=true")))

if __name__=="__main__":
    unittest.main()
