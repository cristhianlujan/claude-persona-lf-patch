#!/usr/bin/env python3
"""Negative/positive regression for the Router intent-consistency guard.

Fixture assertions are NOT evidence of a live semantic model or ACT-0001 cutover.
"""
import copy
import hashlib
import json
import unittest

from router_intent_consistency_v1 import check

REQUEST = (
    "Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B "
    "a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla."
)
TARGET = "PANTALLA-B2B-LOGIN"
INTENT = {
    "schema_version": "LF_ROUTER_INTENT_PROPOSAL_V1",
    "request_sha256": hashlib.sha256(REQUEST.encode()).hexdigest(),
    "semantic_state": "RESOLVED",
    "catalog_revision_sha256": "candidate-catalog-revision",
    "target_type": "PANTALLA",
    "target_code": TARGET,
    "action_code": "SCREEN_UPDATE",
    "allowed_scopes": ["UI.BUTTON.PRIMARY.LABEL"],
    "denied_scopes": ["AUTHENTICATION", "VALIDATION", "UI.OTHER"],
    "evidence": {
        "action_quote": "Cambiar",
        "target_quote": "pantalla Iniciar sesión B2B",
        "allow_quote": "texto del botón principal",
        "deny_quote": "sin modificar la autenticación, las validaciones ni otras partes de la pantalla.",
    },
}
CATALOG = {
    "revision_sha256": "candidate-catalog-revision",
    "type_aliases": {"PANTALLA": ["pantalla"], "ADAPTER": ["adapter", "adaptador"]},
    "assets": {
        TARGET: {"type": "PANTALLA", "active": True},
    },
    "active_routes": [
        {"asset_type": "PANTALLA", "action_code": "SCREEN_UPDATE", "operation_code": "ACTUALIZACION_PANTALLA_LF", "active": True}
    ],
}
CORRECT_ROUTE = {
    "status": "READY_TO_EXECUTE",
    "asset_type": "PANTALLA",
    "action_code": "SCREEN_UPDATE",
    "operation_code": "ACTUALIZACION_PANTALLA_LF",
    "asset": {"codigo_activo": TARGET},
    "declared_effect_scopes": ["UI.BUTTON.PRIMARY.LABEL"],
}
OBSERVED_WRONG_ROUTE = {
    "status": "READY_TO_EXECUTE",
    "asset_type": "ADAPTER",
    "action_code": "ADAPTER_UPDATE",
    "operation_code": "ACTUALIZACION_ADAPTER_LF",
    "asset": {"codigo_activo": "ADAPTER-LF-SHELL-PROFILE-20260827"},
}


def verified(_digest, _proposal):
    # Stub: tests only the deterministic boundary. Real trusted assurance is absent.
    return True


def assess(proposal=None, route=None, catalog=None, verifier=verified, request=REQUEST):
    return check(
        request,
        copy.deepcopy(INTENT if proposal is None else proposal),
        copy.deepcopy(CORRECT_ROUTE if route is None else route),
        copy.deepcopy(CATALOG if catalog is None else catalog),
        verify_semantic_receipt=verifier,
    )


class RouterIntentConsistencyTests(unittest.TestCase):
    def test_original_wrong_adapter_route_must_block(self):
        r = assess(route=OBSERVED_WRONG_ROUTE)
        self.assertEqual(r["blocking_code"], "BLOCK_ROUTER_SEMANTIC_TYPE_MISMATCH")
        self.assertFalse(r["downstream_execution_allowed"])

    def test_semantic_proposal_cannot_self_attest(self):
        r = assess(verifier=None)
        self.assertEqual(r["blocking_code"], "BLOCK_TRUSTED_SEMANTIC_ASSURANCE_MISSING")

    def test_unverified_semantic_receipt_blocks(self):
        self.assertEqual(assess(verifier=lambda _h, _i: False)["blocking_code"], "BLOCK_TRUSTED_SEMANTIC_ASSURANCE_FAILED")

    def test_changed_original_request_blocks(self):
        self.assertEqual(assess(request=REQUEST + " extra")["blocking_code"], "BLOCK_SEMANTIC_INTENT_SOURCE_DRIFT")

    def test_ambiguous_semantic_state_blocks(self):
        x = copy.deepcopy(INTENT)
        x["semantic_state"] = "UNCERTAIN"
        self.assertEqual(assess(proposal=x)["blocking_code"], "BLOCK_SEMANTIC_INTENT_UNRESOLVED")

    def test_catalog_currentness_blocks(self):
        x = copy.deepcopy(CATALOG)
        x["revision_sha256"] = "new-revision"
        self.assertEqual(assess(catalog=x)["blocking_code"], "BLOCK_CATALOG_CURRENTNESS_DRIFT")

    def test_wrong_asset_type_evidence_blocks(self):
        x = copy.deepcopy(INTENT)
        x["target_type"] = "ADAPTER"
        self.assertEqual(assess(proposal=x)["blocking_code"], "BLOCK_SEMANTIC_TARGET_TYPE_UNGROUNDED")

    def test_negation_quote_must_exist_in_source(self):
        x = copy.deepcopy(INTENT)
        x["evidence"]["deny_quote"] = "autenticación podrá modificarse"
        self.assertEqual(assess(proposal=x)["blocking_code"], "BLOCK_NEGATED_SCOPE_EVIDENCE_UNGROUNDED")

    def test_scope_contradiction_blocks(self):
        x = copy.deepcopy(INTENT)
        x["denied_scopes"].append("UI.BUTTON")
        self.assertEqual(assess(proposal=x)["blocking_code"], "BLOCK_SCOPE_CONTRADICTION")

    def test_unregistered_screen_blocks(self):
        x = copy.deepcopy(CATALOG)
        x["assets"] = {}
        self.assertEqual(assess(catalog=x)["blocking_code"], "BLOCK_CANONICAL_TARGET_NOT_REGISTERED")

    def test_unregistered_screen_operation_blocks(self):
        x = copy.deepcopy(CATALOG)
        x["active_routes"] = []
        self.assertEqual(assess(catalog=x)["blocking_code"], "BLOCK_CANONICAL_OPERATION_NOT_REGISTERED")

    def test_broad_effect_overlaps_forbidden_area(self):
        x = copy.deepcopy(CORRECT_ROUTE)
        x["declared_effect_scopes"] = ["UI"]
        self.assertEqual(assess(route=x)["blocking_code"], "BLOCK_ROUTER_FORBIDDEN_EFFECT")

    def test_unrelated_effect_cannot_escape_scoped_copy(self):
        x = copy.deepcopy(CORRECT_ROUTE)
        x["declared_effect_scopes"] = ["UI.SCREEN.REPLACE"]
        self.assertEqual(assess(route=x)["blocking_code"], "BLOCK_ROUTER_EFFECT_OUT_OF_SCOPE")

    def test_forbidden_authentication_effect_blocks(self):
        x = copy.deepcopy(CORRECT_ROUTE)
        x["declared_effect_scopes"].append("AUTHENTICATION")
        self.assertEqual(assess(route=x)["blocking_code"], "BLOCK_ROUTER_FORBIDDEN_EFFECT")

    def test_missing_declared_effects_blocks(self):
        x = copy.deepcopy(CORRECT_ROUTE)
        del x["declared_effect_scopes"]
        self.assertEqual(assess(route=x)["blocking_code"], "BLOCK_ROUTER_EFFECT_SCOPE_UNDECLARED")

    def test_matching_registered_route_is_only_consistency_not_execution(self):
        r = assess()
        self.assertEqual(r["status"], "ROUTE_CONSISTENCY_PASS")
        self.assertFalse(r["downstream_execution_allowed"])
        self.assertFalse(r["effects_executed"])

    def test_determinism_for_identical_inputs(self):
        self.assertEqual(assess(), assess())


if __name__ == "__main__":
    unittest.main(verbosity=2)
