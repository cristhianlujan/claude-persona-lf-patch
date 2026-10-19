#!/usr/bin/env python3
"""Negative and positive checks for ACT-0001 semantic review, not runtime proof."""
import copy
import hashlib
import unittest

from router_intent_semantic_contract_v1 import validate_semantic_handoff

FILE = "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py"
REQUEST = (
    f"Actualizar exclusivamente el archivo {FILE} para fortalecer NO_FALSE_PASS; "
    "conservar FAIL_CLOSED sin modificar runtime, contratos ni otros archivos."
)
REF = "cristhianlujan/claude-persona-lf-patch:" + FILE


def digest(value=REQUEST):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def fixture(request=REQUEST, refs=None):
    refs = refs if refs is not None else [{
        "plan_code": "IG_CURATOR_VALIDATOR_REFACTOR_V2",
        "unit_code": "M10.7",
        "checkpoint_code": "NO_FALSE_PASS",
        "artifact_ref": REF,
        "mutation_policy": "TEST_ARTIFACT_ONLY",
    }]
    return {
        "router": "ACT-0001",
        "source": "SUPABASE",
        "status": "BLOCKED",
        "blocking_code": "BLOCK_ARTIFACT_CONSUMER_UNATTESTED",
        "downstream_execution_allowed": False,
        "request_sha256": digest(request),
        "semantic_handoff": {
            "schema_version": "LF_ROUTER_INTENT_HANDOFF_V1",
            "literal_request": request,
            "request_sha256": digest(request),
            "candidate_subjects": refs,
            "scope_binding_state": "UNATTESTED",
            "semantic_consumer_receipt": None,
            "executor_binding_state": "NOT_SELECTED",
            "downstream_execution_allowed": False,
        },
    }


def proposal(positive=None, excluded=None):
    return {
        "request_sha256": digest(),
        "positive_target_refs": [REF] if positive is None else positive,
        "excluded_target_refs": [] if excluded is None else excluded,
        "objective": "Strengthen exact negative checkpoint test",
        "forbidden_scope": ["runtime", "contracts", "other files"],
        "trusted": True,  # Self-declared trust must not grant execution authority.
    }


class RouterSemanticHandoffTests(unittest.TestCase):
    def test_exact_artifact_is_preserved_as_advisory(self):
        result = validate_semantic_handoff(REQUEST, fixture())
        self.assertEqual(result["status"], "ADVISORY_ONLY")
        self.assertEqual(result["literal_request"], REQUEST)
        self.assertEqual(result["canonical_subject_refs"], [REF])
        self.assertEqual(result["next"], "GOVERNED_SEMANTIC_CONSUMER_RESOLUTION")
        self.assertFalse(result["downstream_execution_allowed"])

    def test_proposed_scope_never_authorizes_execution(self):
        result = validate_semantic_handoff(REQUEST, fixture(), proposal())
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertEqual(result["proposed_forbidden_scope"],
                         ["runtime", "contracts", "other files"])
        self.assertEqual(result["scope_binding_state"], "CANDIDATE_UNATTESTED")
        self.assertIsNone(result["execution_receipt"])
        self.assertFalse(result["downstream_execution_allowed"])

    def test_original_request_changes_fail_closed(self):
        result = validate_semantic_handoff(REQUEST + " ", fixture())
        self.assertEqual(result["blocking_code"], "BLOCK_ROUTER_OR_LITERAL_DRIFT")

    def test_semantic_handoff_cannot_be_replaced(self):
        route = fixture()
        route["semantic_handoff"]["literal_request"] = "Unrelated"
        result = validate_semantic_handoff(REQUEST, route)
        self.assertEqual(result["blocking_code"], "BLOCK_SEMANTIC_HANDOFF_DRIFT")

    def test_artifact_path_must_be_literal_exact(self):
        other_ref = "owner/repo:elsewhere/negative.py"
        route = fixture(refs=[{"artifact_ref": other_ref}])
        result = validate_semantic_handoff(REQUEST, route)
        self.assertEqual(result["blocking_code"], "BLOCK_ARTIFACT_LITERAL_MISMATCH")

    def test_unknown_positive_target_is_rejected(self):
        value = proposal(positive=["ACT-0013"])
        result = validate_semantic_handoff(REQUEST, fixture(), value)
        self.assertEqual(result["blocking_code"], "BLOCK_PROPOSED_TARGET_NOT_IN_CANON")

    def test_overlap_positive_and_exclusion_is_rejected(self):
        value = proposal(excluded=[REF])
        result = validate_semantic_handoff(REQUEST, fixture(), value)
        self.assertEqual(result["blocking_code"],
                         "BLOCK_POSITIVE_EXCLUDED_SCOPE_OVERLAP")

    def test_multiple_subjects_require_all_roles(self):
        ref2 = "ACT-0052"
        req = "Actualizar ACT-0053 pero no modificar ACT-0052"
        route = fixture(request=req, refs=[
            {"asset_code": "ACT-0053"}, {"asset_code": ref2},
        ])
        p = {
            "request_sha256": digest(req),
            "positive_target_refs": ["ACT-0053"],
            "excluded_target_refs": [],
            "objective": "Modify exact target only",
            "forbidden_scope": ["ACT-0052"],
        }
        self.assertEqual(
            validate_semantic_handoff(req, route, p)["blocking_code"],
            "BLOCK_CANDIDATE_ROLES_UNRESOLVED",
        )
        p["excluded_target_refs"] = ["ACT-0052"]
        res = validate_semantic_handoff(req, route, p)
        self.assertEqual(res["status"], "REVIEW_REQUIRED")
        self.assertEqual(res["proposed_excluded_target_refs"], ["ACT-0052"])
        self.assertFalse(res["downstream_execution_allowed"])

    def test_forged_execution_flag_is_rejected(self):
        route = fixture()
        route["downstream_execution_allowed"] = True
        self.assertEqual(
            validate_semantic_handoff(REQUEST, route)["blocking_code"],
            "BLOCK_ROUTER_OR_LITERAL_DRIFT",
        )

    def test_forged_consumer_receipt_is_rejected(self):
        route = fixture()
        route["semantic_handoff"]["semantic_consumer_receipt"] = {
            "self_attested": True
        }
        self.assertEqual(
            validate_semantic_handoff(REQUEST, route)["blocking_code"],
            "BLOCK_SEMANTIC_HANDOFF_DRIFT",
        )

    def test_screen_candidate_is_an_advisory_subject_not_executor(self):
        req = "Cambiar texto en la pantalla Iniciar sesión B2B sin tocar autenticación"
        route = fixture(request=req, refs=[{"screen_code": "B2B-AUTH-001"}])
        res = validate_semantic_handoff(req, route)
        self.assertEqual(res["canonical_subject_refs"], ["B2B-AUTH-001"])
        self.assertIsNone(res["executor_selected"])
        self.assertFalse(res["downstream_execution_allowed"])

    def test_missing_negative_scope_is_a_candidate_not_pass(self):
        value = proposal()
        value["forbidden_scope"] = []
        res = validate_semantic_handoff(REQUEST, fixture(), value)
        self.assertEqual(res["status"], "REVIEW_REQUIRED")
        self.assertFalse(res["downstream_execution_allowed"])

    def test_missing_explicit_positive_target_blocks(self):
        value = proposal(positive=[])
        res = validate_semantic_handoff(REQUEST, fixture(), value)
        self.assertEqual(res["blocking_code"], "BLOCK_POSITIVE_TARGET_MISSING")


if __name__ == "__main__":
    unittest.main()
