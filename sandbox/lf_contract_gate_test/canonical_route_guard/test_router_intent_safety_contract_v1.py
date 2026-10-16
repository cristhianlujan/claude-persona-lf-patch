"""Phase 1 adversarial checks for the EXISTING #2774 candidate.

TDD: these are contract-level tests with a STUB semantic verifier.
They are not an authority receipt or live ACT-0001 prewrite proof.
"""
import copy
import hashlib
import unittest

from router_intent_consistency_v1 import check
from test_router_intent_consistency_v1 import INTENT, CATALOG, CORRECT_ROUTE, REQUEST, verified


def invoke(*, request=REQUEST, proposal=None, catalog=None, route=None):
    p = copy.deepcopy(INTENT if proposal is None else proposal)
    p["request_sha256"] = hashlib.sha256(request.encode("utf-8")).hexdigest()
    return check(request, p,
                 copy.deepcopy(CORRECT_ROUTE if route is None else route),
                 copy.deepcopy(CATALOG if catalog is None else catalog),
                 verify_semantic_receipt=verified)


def pbase():
    x = copy.deepcopy(INTENT)
    x.update(requested_mode="EXECUTE", excluded_target_codes=[],
             work_units=[{"target_type":"PANTALLA","target_code":"B2B-AUTH-001","action_code":"SCREEN_UPDATE"}],
             condition_state="NOT_APPLICABLE")
    return x


class SafetyEnvelopeTests(unittest.TestCase):
    def blocked(self, code, **kw):
        r = invoke(**kw)
        self.assertEqual(r["status"], "BLOCKED", r)
        self.assertEqual(r["blocking_code"], code, r)
        self.assertIs(r["downstream_execution_allowed"], False)

    def test_missing_mode_not_silent_execute(self):
        p = pbase(); p.pop("requested_mode")
        self.blocked("BLOCK_REQUEST_MODE_UNATTESTED", proposal=p)

    def test_simulation_never_becomes_effect_route(self):
        p = pbase(); p["requested_mode"]="SIMULATE"
        self.blocked("BLOCK_NON_EXECUTION_MODE_EFFECTS", proposal=p)

    def test_exploration_never_becomes_effect_route(self):
        p = pbase(); p["requested_mode"]="EXPLORE"
        self.blocked("BLOCK_NON_EXECUTION_MODE_EFFECTS", proposal=p)

    def test_analysis_never_becomes_effect_route(self):
        p = pbase(); p["requested_mode"]="ANALYZE"
        self.blocked("BLOCK_NON_EXECUTION_MODE_EFFECTS", proposal=p)

    def test_prepare_never_becomes_effect_route(self):
        p = pbase(); p["requested_mode"]="PREPARE"
        self.blocked("BLOCK_NON_EXECUTION_MODE_EFFECTS", proposal=p)

    def test_unknown_mode_cannot_default_to_execute(self):
        p = pbase(); p["requested_mode"]="UNSPECIFIED"
        self.blocked("BLOCK_REQUEST_MODE_UNATTESTED", proposal=p)

    def test_missing_excluded_target_set_cannot_default_empty(self):
        p = pbase(); p.pop("excluded_target_codes")
        self.blocked("BLOCK_EXCLUDED_TARGET_SET_UNATTESTED", proposal=p)

    def test_excluded_target_never_passes_even_with_code_match(self):
        p = pbase();p["excluded_target_codes"]=["B2B-AUTH-001"]
        p["evidence"]["excluded_targets_quote"]="pantalla Iniciar sesión B2B"
        self.blocked("BLOCK_ROUTER_EXCLUDED_TARGET", proposal=p)

    def test_exclusion_without_evidence_cannot_pass(self):
        p = pbase();p["excluded_target_codes"]=["OTHER-SCREEN"]
        self.blocked("BLOCK_EXCLUDED_TARGET_EVIDENCE_UNGROUNDED", proposal=p)

    def test_exclusion_of_unrelated_asset_can_preserve_positive(self):
        p = pbase();p["excluded_target_codes"]=["AUTH-SECONDARY"]
        p["evidence"]["excluded_targets_quote"]="sin modificar la autenticación"
        self.assertEqual(invoke(proposal=p)["status"],"ROUTE_CONSISTENCY_PASS")

    def test_no_silent_loss_of_second_work_unit(self):
        p = pbase();p["work_units"].append({"target_type":"REGLA","target_code":"R-2","action_code":"REGLA_CREATE"})
        self.blocked("BLOCK_ROUTER_COMPOSITE_COVERAGE_INCOMPLETE", proposal=p)

    def test_missing_work_units_cannot_invent_one(self):
        p = pbase();p.pop("work_units")
        self.blocked("BLOCK_WORK_UNITS_UNATTESTED", proposal=p)

    def test_mismatched_single_unit_cannot_pass(self):
        p = pbase();p["work_units"][0]["target_code"]="OTHER-SCREEN"
        self.blocked("BLOCK_WORK_UNIT_ROUTE_MISMATCH", proposal=p)

    def test_conditional_write_needs_condition_receipt(self):
        p = pbase();p["condition_state"]="UNRESOLVED"
        self.blocked("BLOCK_CONDITIONAL_EFFECT_UNRESOLVED", proposal=p)

    def test_missing_condition_state_cannot_assume_unconditional(self):
        p = pbase();p.pop("condition_state")
        self.blocked("BLOCK_CONDITION_STATE_UNATTESTED", proposal=p)

    def test_single_exec_valid_remains_consistency_only(self):
        r=invoke(proposal=pbase());self.assertEqual(r["status"],"ROUTE_CONSISTENCY_PASS")
        self.assertFalse(r["downstream_execution_allowed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
