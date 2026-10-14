"""Positive and adversarial tests. These never connect to Supabase or deploy."""
import copy
import unittest
from edge_deploy_guard_v1 import preflight, OPERATION

A = "a" * 40
B = "b" * 40

def packet():
    return {
        "operation_code": OPERATION, "function_slug": "lf-profiles-governance-caller-v1",
        "target_type": "SUPABASE_EDGE_FUNCTION",
        "target_path": "supabase/functions/lf-profiles-governance-caller-v1",
        "source_sha": A, "main_sha": A, "rollback_sha": B,
        "rollback_source_equals_deployed": True,
        "only_target_function_changed": True,
        "jwt_mode_preserved": True, "db_write_required": False,
        "no_release_promotion": True, "execute": False,
    }

def ready():
    p = packet()
    p.update({
        "execute": True,
        "r17": {"status": "READY_NO_PROVIDER_EFFECT", "event_id": "R17-001",
                "offline_bundle_receipt": "BUNDLE-1",
                "offline_rollback": "PASS", "offline_idempotency": "PASS",
                "provider_deployment_executed": False,
                "p50_ms": 10, "p90_ms": 20, "max_ms": 30},
        "operation_authority": "CURRENT_VERIFIED",
        "effect_guard": "RESERVED_EXACT",
        "human_runtime_authorization": "SIGNED_CURRENT",
    })
    return p

class EdgeOperationGuardTests(unittest.TestCase):
    def assert_blocked(self, data, code):
        with self.assertRaisesRegex(ValueError, code):
            preflight(data)
    def test_dry_run_baseline(self):
        r = preflight(packet())
        self.assertEqual(r["verdict"], "DRY_RUN_ONLY")
        self.assertFalse(r["effect_executed"])
    def test_positive_only_with_all_receipts(self):
        r = preflight(ready())
        self.assertEqual(r["verdict"], "READY_FOR_GOVERNED_DEPLOY")
        self.assertFalse(r["effect_executed"])
    def test_other_operation_blocked(self):
        p = packet(); p["operation_code"] = "REFRESCO_RUNTIME_PERFIL_LF"
        self.assert_blocked(p, "OPERATION_ROUTE_MISMATCH")
    def test_target_escape_blocked(self):
        p = packet(); p["target_path"] = "supabase/functions/other"
        self.assert_blocked(p, "TARGET_PATH_MISMATCH")
    def test_non_main_sha_blocked(self):
        p = packet(); p["main_sha"] = "c"*40
        self.assert_blocked(p, "SOURCE_NOT_EXACT_MAIN")
    def test_no_rollback_blocked(self):
        p = packet(); p["rollback_source_equals_deployed"] = False
        self.assert_blocked(p, "ROLLBACK_NOT_LIVE_VERIFIED")
    def test_other_function_delta_blocked(self):
        p = packet(); p["only_target_function_changed"] = False
        self.assert_blocked(p, "OTHER_FUNCTION_DELTA")
    def test_jwt_change_blocked(self):
        p = packet(); p["jwt_mode_preserved"] = False
        self.assert_blocked(p, "JWT_MODE_DRIFT")
    def test_no_r17_not_deployable(self):
        p = ready(); p["r17"]["status"] = "PENDING"
        self.assert_blocked(p, "R17_PREFLIGHT_NOT_PASSED")
    def test_preflight_must_not_claim_provider_pass(self):
        p = ready(); p["r17"]["status"] = "PASS"
        self.assert_blocked(p, "R17_PREFLIGHT_NOT_PASSED")
        p = ready(); p["r17"]["provider_deployment_executed"] = True
        self.assert_blocked(p, "R17_PROVIDER_ALREADY_DEPLOYED")
        p = ready(); p["r17"]["offline_idempotency"] = "PENDING"
        self.assert_blocked(p, "R17_OFFLINE_IDEMPOTENCY_NOT_VERIFIED")

    def test_no_human_authorization(self):
        p = ready(); p["human_runtime_authorization"] = "PENDING"
        self.assert_blocked(p, "DEPLOY_NOT_AUTHORIZED")
    def test_no_effect_guard(self):
        p = ready(); p["effect_guard"] = "UNKNOWN"
        self.assert_blocked(p, "EFFECT_GUARD_MISSING")
    def test_replay_rollback_equals_source(self):
        p = packet(); p["rollback_sha"] = A
        self.assert_blocked(p, "ROLLBACK_EQUALS_SOURCE")
    def test_no_manual_promotion(self):
        p = packet(); p["no_release_promotion"] = False
        self.assert_blocked(p, "RELEASE_PROMOTION_FORBIDDEN")
    def test_bad_time_order(self):
        p = ready(); p["r17"]["p50_ms"] = 40
        self.assert_blocked(p, "R17_TIMING_INCONSISTENT")
    def test_no_r17_event(self):
        p = ready(); p["r17"]["event_id"] = ""
        self.assert_blocked(p, "R17_EVENT_MISSING")

if __name__ == "__main__":
    unittest.main()
