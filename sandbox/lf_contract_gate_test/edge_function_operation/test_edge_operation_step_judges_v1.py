"""Positive and negative checks for each of the eight Edge Operation steps."""
import copy
import unittest
from edge_operation_step_judges_v1 import validate_step, STEPS, OPERATION

A = "a" * 40
B = "b" * 40
C = "c" * 64

def fixture():
    a = {
        "source_kind": "CANONICAL_INDEPENDENT_READBACK",
        "operation_code": OPERATION, "target_type": "SUPABASE_EDGE_FUNCTION",
        "target": "lf-profiles-governance-caller-v1", "target_count": 1,
        "main_sha": A, "execution_id": "EX-1", "operation_execution_state": "IN_PROGRESS",
        "deployed_rollback_git_sha": B, "rollback_bytes_equal_live": True,
        "only_target_changed": True, "jwt_mode_preserved": True,
        "r17_event_id": "R17-1", "offline_bundle_receipt": "BUNDLE-1",
        "offline_rollback_verified": True, "offline_idempotency_verified": True,
        "r17_predeploy_state": "READY_NO_PROVIDER_EFFECT",
        "provider_deployment_executed": False,
        "provider_rollback_receipt": "REAL-ROLLBACK-1",
        "provider_idempotency_receipt": "REAL-REPLAY-1",
        "provider_rollback_drill_executed": True, "provider_idempotency_drill_executed": True,
        "provider_source_restored": True, "timing": {"p50_ms": 10, "p90_ms": 20, "max_ms": 30}, "time_budget_ms": 100,
        "human_receipt_id": "SUPER-1", "human_role": "SUPER_ADMIN",
        "human_decision": "APPROVE_DEPLOY", "operation_lifecycle": "OP_OPERATIONAL",
        "authorized_target": "lf-profiles-governance-caller-v1",
        "route_write_allowed": True, "runtime_effect_enabled": True,
        "effect_scope": "SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1",
        "request_sha256": C, "reservation_receipt": "RES-1",
        "effect_state": "RESERVED", "dispatch_permitted": True,
        "deploy_execution_id": "D-1", "provider_receipt": "P-1",
        "provider_target": "lf-profiles-governance-caller-v1", "provider_deployed": True,
        "deployed_source_sha": A, "oidc_probe_receipt": "OIDC-1",
        "rollback_state": "READY", "oidc_action_scope_mismatch": False,
        "prior_verify_jwt": False, "deployed_verify_jwt": False,
        "cp2_jobs_started": 0, "effect_guard_receipt": "E-1",
        "independent_parity": "PASS", "open_blockers": [], "release_promoted": False,
    }
    e = {
        "init_execution": {"execution_id": "EX-1", "target_code": a["target"]},
        "source_baseline": {"exact_main_sha": A, "rollback_sha": B, "live_source_parity": True},
        "r17_preflight": {"r17_event_id": "R17-1", "timing": dict(a["timing"]),
                           "offline_bundle_receipt": "BUNDLE-1",
                           "offline_rollback": "PASS", "offline_idempotency": "PASS"},
        "human_authority": {"signed_receipt": "SUPER-1", "operation_current": True, "scope_exact": True},
        "effect_guard": {"effect_scope": a["effect_scope"], "request_sha256": C,
                         "reservation_receipt": "RES-1"},
        "edge_deploy": {"deploy_execution_id": "D-1", "provider_receipt": "P-1", "source_sha": A},
        "independent_readback": {"deployed_source": A, "oidc_probe": "OIDC-1", "rollback_state": "READY",
                                 "provider_rollback_receipt": "REAL-ROLLBACK-1",
                                 "provider_idempotency_receipt": "REAL-REPLAY-1"},
        "close": {"effect_guard_receipt": "E-1", "parity": "PASS", "open_blockers": []},
    }
    return a, e

class EdgeStepJudgesTests(unittest.TestCase):
    def test_all_eight_positive(self):
        a,e = fixture()
        self.assertEqual(len(STEPS), 8)
        for step in STEPS:
            with self.subTest(step=step):
                context = dict(a, effect_state="SUCCEEDED") if step == "close" else a
                result = validate_step(step, e[step], context)
                self.assertTrue(result["valid"])
                self.assertEqual(result["server_assertions"], ["edge_" + step + "_verified"])

    def test_all_eight_negative_missing_evidence(self):
        a,e = fixture()
        for step in STEPS:
            with self.subTest(step=step):
                evidence = dict(e[step])
                evidence.pop(next(iter(evidence)))
                context = dict(a, effect_state="SUCCEEDED") if step == "close" else a
                with self.assertRaisesRegex(ValueError, "EDGE_" + step.upper()):
                    validate_step(step, evidence, context)

    def test_wrong_authority_fails_every_step(self):
        a,e = fixture()
        for step in STEPS:
            with self.subTest(step=step):
                b = dict(a, source_kind="USER_SUPPLIED")
                with self.assertRaisesRegex(ValueError, "EDGE_UNTRUSTED_AUTHORITY_SOURCE"):
                    validate_step(step, e[step], b)

    def test_operation_and_target_identity_rejected(self):
        a,e = fixture()
        for fld,bad,code in (
            ("operation_code","REFRESCO_RUNTIME_PERFIL_LF","EDGE_WRONG_OPERATION"),
            ("target_type","PERFIL","EDGE_WRONG_TARGET_TYPE"),
            ("target_count",2,"EDGE_TARGET_COUNT")
        ):
            with self.subTest(field=fld):
                with self.assertRaisesRegex(ValueError,code):
                    validate_step("init_execution", e["init_execution"], dict(a,**{fld:bad}))

    def test_source_drift_rejected(self):
        a,e = fixture()
        for fld,bad in (("rollback_bytes_equal_live",False),("only_target_changed",False),("jwt_mode_preserved",False)):
            with self.subTest(field=fld):
                with self.assertRaises(ValueError):
                    validate_step("source_baseline", e["source_baseline"], dict(a,**{fld:bad}))

    def test_r17_missing_event_not_success(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError, "EDGE_R17_PREFLIGHT_EVENT"):
            validate_step("r17_preflight", dict(e["r17_preflight"],r17_event_id=""), a)

    def test_r17_out_of_budget(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError, "EDGE_R17_PREFLIGHT_TIME_BUDGET"):
            validate_step("r17_preflight", e["r17_preflight"], dict(a,time_budget_ms=10))

    def test_r17_forged_time_rejected(self):
        a,e = fixture()
        fake=copy.deepcopy(e["r17_preflight"])
        fake["timing"]["p90_ms"]=1
        with self.assertRaises(ValueError):
            validate_step("r17_preflight", fake, a)

    def test_predeploy_rejects_false_provider_effect(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError, "EDGE_R17_PREFLIGHT_PREFLIGHT_ONLY"):
            validate_step("r17_preflight", e["r17_preflight"],
                          dict(a, provider_deployment_executed=True))
        for field in ("offline_rollback_verified", "offline_idempotency_verified"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_step("r17_preflight", e["r17_preflight"], dict(a, **{field: False}))

    def test_no_closure_without_live_provider_rollback_and_idempotency(self):
        a,e = fixture()
        for field in ("provider_rollback_drill_executed",
                      "provider_idempotency_drill_executed", "provider_source_restored"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_step("independent_readback", e["independent_readback"],
                              dict(a, **{field: False}))

    def test_human_gate_and_candidate_route_block(self):
        a,e = fixture()
        for key,bad in (("human_role","USER"),("route_write_allowed",False),("operation_lifecycle","OP_CANDIDATE")):
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    validate_step("human_authority",e["human_authority"],dict(a,**{key:bad}))

    def test_effect_requires_reserved_state(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError,"EDGE_EFFECT_GUARD_EFFECT_NOT_RESERVED"):
            validate_step("effect_guard",e["effect_guard"],dict(a,effect_state="SUCCEEDED"))

    def test_provider_target_is_exact(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError,"EDGE_EDGE_DEPLOY_PROVIDER_TARGET"):
            validate_step("edge_deploy",e["edge_deploy"],dict(a,provider_target="other"))

    def test_independent_readback_fails_scope_mismatch(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError,"EDGE_INDEPENDENT_READBACK_OIDC_SCOPE_MISMATCH"):
            validate_step("independent_readback",e["independent_readback"],dict(a,oidc_action_scope_mismatch=True))

    def test_independent_readback_fails_jwt_drift(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError,"EDGE_INDEPENDENT_READBACK_JWT_MODE_DRIFT"):
            validate_step("independent_readback",e["independent_readback"],dict(a,deployed_verify_jwt=True))

    def test_deploy_never_runs_cp2(self):
        a,e = fixture()
        for step in ("independent_readback", "close"):
            b = dict(a, cp2_jobs_started=1, effect_state="SUCCEEDED")
            with self.subTest(step=step), self.assertRaises(ValueError):
                validate_step(step,e[step],b)

    def test_close_fails_auto_promotion(self):
        a,e = fixture()
        with self.assertRaisesRegex(ValueError,"EDGE_CLOSE_EFFECT_OR_PROMOTION"):
            validate_step("close",e["close"],dict(a,effect_state="SUCCEEDED",release_promoted=True))

    def test_close_positive_completed(self):
        a,e = fixture()
        a["effect_state"]="SUCCEEDED"
        self.assertTrue(validate_step("close",e["close"],a)["valid"])

if __name__ == "__main__":
    unittest.main()
