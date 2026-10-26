"""Synthetic local checks for the opt-in A6/A9 preview; no database writes."""
from copy import deepcopy
import json
from pathlib import Path
import unittest

from analysis_a6_a9_preview_v1 import (
    ENTRY_DIGEST, assemble_a6_a9_preview_v1, validate_a6_payload_v1,
    canonical_sha256,
)

HERE = Path(__file__).resolve().parent


class AssemblyPreviewTests(unittest.TestCase):
    def setUp(self):
        self.snapshot = json.loads((HERE / "fixtures/programming_pg01_receiver_base_v1.json").read_text())["context"]["extensions"]["programming_context_snapshot"]
        self.a6 = deepcopy(self.snapshot.pop("implementability_schema"))
        self.snapshot.pop("scope_front_matrix")
        self.snapshot["snapshot_schema_digest_sha256"] = ENTRY_DIGEST

    def run_preview(self):
        return assemble_a6_a9_preview_v1(self.snapshot, self.a6, canonical_sha256(self.a6))

    def assert_rejected(self, code):
        result = self.run_preview()
        self.assertEqual(result["status"], "RETURN_TO_ANALYSIS")
        self.assertIsNone(result["candidate_snapshot"])
        self.assertIn(code, [i["code"] for i in result["issues"]])
        return result

    def test_complete_a6_preserved_without_permission_or_mutation(self):
        self.a6["extra_provenance"] = {"ref": "fixture://extra"}
        before = deepcopy((self.snapshot, self.a6))
        result = self.run_preview()
        self.assertEqual(result["status"], "CANDIDATE_ASSEMBLED")
        self.assertEqual(result["candidate_snapshot"]["implementability_schema"], self.a6)
        self.assertEqual(result["ready_scope_ids"], ["S1"])
        self.assertEqual((self.snapshot, self.a6), before)
        for field in ("planning_allowed", "execution_allowed", "persistence_allowed", "operational_admission"):
            self.assertIs(result[field], False)
        result["candidate_snapshot"]["implementability_schema"]["extra_provenance"]["ref"] = "changed"
        self.assertEqual((self.snapshot, self.a6), before)

    def test_deterministic(self):
        self.assertEqual(self.run_preview(), self.run_preview())

    def test_missing_four_historical_a6_fields_diagnosed_together(self):
        for key in ("requirements", "canonical_implementation_bindings", "currentness_refs", "implementability_fingerprint_sha256"):
            self.a6.pop(key)
        result = self.assert_rejected("A6_REQUIRED_FIELD_MISSING")
        paths = {i["path"] for i in result["issues"]}
        self.assertTrue({"requirements", "canonical_implementation_bindings", "currentness_refs", "implementability_fingerprint_sha256"}.issubset(paths))

    def test_bad_artifact_digest(self):
        result = assemble_a6_a9_preview_v1(self.snapshot, self.a6, "0" * 64)
        self.assertEqual(result["issues"][0]["code"], "A6_EXPECTED_ARTIFACT_DIGEST_MISMATCH")

    def test_digest_and_schema_are_not_rewritten(self):
        self.snapshot["snapshot_schema_digest_sha256"] = "0" * 64
        self.assert_rejected("A9_ENTRY_DIGEST_MISMATCH")

    def test_recorded_context_envelope_is_rejected(self):
        self.snapshot["context_id"] = "fixture-id"
        self.assert_rejected("RECORDED_CONTEXT_REWRITE_FORBIDDEN")

    def test_existing_a6_conflict(self):
        self.snapshot["implementability_schema"] = {"schema_version": "IMPLEMENTABILITY_SCHEMA_V1"}
        self.assert_rejected("A6_EXISTING_ARTIFACT_CONFLICT")

    def test_existing_identical_a6_is_reused(self):
        self.snapshot["implementability_schema"] = deepcopy(self.a6)
        self.assertEqual(self.run_preview()["status"], "CANDIDATE_ASSEMBLED")

    def test_missing_requirements_not_filled(self):
        self.a6["requirements"] = []
        self.assert_rejected("A6_A9_REQUIREMENT_IDENTITY_MISMATCH")

    def test_duplicate_requirement(self):
        self.a6["requirements"] *= 2
        self.assert_rejected("A6_IDENTITY_INVALID_OR_DUPLICATE")

    def test_requirement_unknown_scope(self):
        self.a6["requirements"][0]["scope_refs"] = ["OTHER"]
        self.assert_rejected("A6_UNKNOWN_OR_MISSING_SCOPE")

    def test_requirement_missing_refs_no_defaults(self):
        self.a6["requirements"][0].pop("permission_refs")
        self.assert_rejected("A6_REQUIRED_FIELD_MISSING")

    def test_unknown_effect_requires_blocker(self):
        self.a6["requirements"][0]["side_effect_class"] = "UNKNOWN"
        self.assert_rejected("A6_UNKNOWN_MATERIAL_WITHOUT_BLOCKER")

    def test_ready_scope_cannot_hide_a6_blocker(self):
        self.a6["requirements"][0]["blockers"] = ["SOURCE_PENDING"]
        self.assert_rejected("A6_MATERIAL_NOT_CLEARED_FOR_READY_SCOPE")

    def test_unresolved_material_cannot_hide_under_ready(self):
        self.a6["unresolved_material_items"] = [{"scope_refs": ["S1"], "reason": "pending"}]
        self.assert_rejected("A6_MATERIAL_NOT_CLEARED_FOR_READY_SCOPE")

    def test_blocked_scope_is_preserved_not_promoted(self):
        self.snapshot["scope_readiness"][0].update(status="NEED_MORE_EVIDENCE", blockers=["SOURCE_PENDING"])
        self.snapshot["package_readiness"] = "NEED_MORE_EVIDENCE"
        self.a6["requirements"][0]["blockers"] = ["SOURCE_PENDING"]
        self.snapshot["source_currentness_qualification"] = "NOT_ADMITTED"
        self.snapshot["operational_integration_admissible"] = False
        result = self.run_preview()
        self.assertEqual(result["status"], "CANDIDATE_ASSEMBLED")
        self.assertEqual(result["ready_scope_ids"], [])
        self.assertEqual(result["candidate_snapshot"]["package_readiness"], "NEED_MORE_EVIDENCE")
        self.assertEqual(result["candidate_snapshot"]["source_currentness_qualification"], "NOT_ADMITTED")
        self.assertIs(result["candidate_snapshot"]["operational_integration_admissible"], False)

    def test_existing_matrix_conflict_is_not_overwritten(self):
        self.snapshot["scope_front_matrix"] = [{"scope_id": "OTHER"}]
        result = self.run_preview()
        self.assertEqual(result["status"], "RETURN_TO_ANALYSIS")
        self.assertIsNone(result["candidate_snapshot"])
        self.assertTrue(result["issues"][0]["code"].startswith("A9_MATRIX_VALIDATION:"))

    def test_valid_existing_matrix_and_extra_metadata_are_preserved(self):
        generated = self.run_preview()["candidate_snapshot"]["scope_front_matrix"]
        generated[0]["extra_source_metadata"] = {"ref": "fixture://original"}
        generated[0]["reason"] = "Original producer reason"
        self.snapshot["scope_front_matrix"] = generated
        result = self.run_preview()
        self.assertEqual(result["status"], "CANDIDATE_ASSEMBLED")
        self.assertEqual(result["candidate_snapshot"]["scope_front_matrix"], generated)

    def test_a7_mismatch_reuses_canonical_rejection(self):
        self.snapshot["material_front_coverage"]["material_fronts"][0]["scope_refs"] = ["OTHER"]
        result = self.run_preview()
        self.assertEqual(result["status"], "RETURN_TO_ANALYSIS")
        self.assertTrue(result["issues"][0]["code"].startswith("A9_MATRIX_VALIDATION:"))

    def binding(self, transport="INLINE_RESOLVED_VALUE_PLUS_CANONICAL_REF"):
        return {"binding_id": "B1", "scope_refs": ["S1"], "binding_kind": "FIXTURE_KIND",
                "canonical_ref": "fixture://value", "resolved_current_value": {"text": "fixture"},
                "value_transport": transport, "currentness_ref": "fixture://current",
                "resolver_ref": "fixture://typed-resolver", "implementation_obligation": "MUST_PRESERVE_EXACT",
                "evidence_refs": ["fixture://evidence"], "blockers": []}

    def test_inline_binding_preserved(self):
        self.a6["canonical_implementation_bindings"] = [self.binding()]
        self.assertEqual(self.run_preview()["status"], "CANDIDATE_ASSEMBLED")

    def test_deferred_transport_preserved_without_fake_resolution(self):
        b = self.binding("EXACT_REF_PLUS_TYPED_RESOLVER")
        b["resolved_current_value"] = None
        self.a6["canonical_implementation_bindings"] = [b]
        result = self.run_preview()
        self.assertEqual(result["status"], "CANDIDATE_ASSEMBLED")
        self.assertIsNone(result["candidate_snapshot"]["implementability_schema"]["canonical_implementation_bindings"][0]["resolved_current_value"])

    def test_deferred_transport_requires_resolver(self):
        b = self.binding("EXACT_REF_ONLY"); b["resolver_ref"] = None
        self.a6["canonical_implementation_bindings"] = [b]
        self.assert_rejected("A6_TYPED_RESOLVER_REQUIRED")

    def test_inline_null_value_rejected(self):
        b = self.binding(); b["resolved_current_value"] = None
        self.a6["canonical_implementation_bindings"] = [b]
        self.assert_rejected("A6_INLINE_VALUE_REQUIRED")

    def test_duplicate_binding(self):
        self.a6["canonical_implementation_bindings"] = [self.binding(), self.binding()]
        self.assert_rejected("A6_IDENTITY_INVALID_OR_DUPLICATE")

    def test_technical_strategy_not_allowed(self):
        self.a6["extra"] = {"chosen_endpoint_design": "invented"}
        self.assert_rejected("A6_TECHNICAL_STRATEGY_FORBIDDEN")

    def test_malformed_json_and_lists_return_diagnostics(self):
        for value in (None, [], True, {"value": float("nan")}, {"value": (1, 2)}):
            with self.subTest(value=value):
                result = assemble_a6_a9_preview_v1(self.snapshot, value, "a" * 64)
                self.assertEqual(result["status"], "RETURN_TO_ANALYSIS")
        for field in ("scope_refs", "blockers", "authority_refs"):
            a6 = deepcopy(self.a6); a6["requirements"][0][field] = True
            self.assertTrue(validate_a6_payload_v1(a6, ["S1"]))
        b = self.binding(); b["value_transport"] = []
        a6 = deepcopy(self.a6); a6["canonical_implementation_bindings"] = [b]
        self.assertTrue(validate_a6_payload_v1(a6, ["S1"]))

    def test_independent_blocked_scope_does_not_contaminate_ready_scope(self):
        self.snapshot["package_readiness"] = "PARTIAL_READY"
        s2 = deepcopy(self.snapshot["scope_readiness"][0])
        s2.update(scope_id="S2", status="BLOCKED", blockers=["OTHER_PENDING"], material_front_refs=["F2"])
        self.snapshot["scope_readiness"].append(s2)
        f2 = deepcopy(self.snapshot["material_front_coverage"]["material_fronts"][0])
        f2.update(front_id="F2", scope_refs=["S2"], closure="BLOCKED", blockers=["OTHER_PENDING"])
        self.snapshot["material_front_coverage"]["material_fronts"].append(f2)
        self.a6["unresolved_material_items"] = [{"scope_refs": ["S2"], "reason": "OTHER_PENDING"}]
        result = self.run_preview()
        self.assertEqual(result["status"], "CANDIDATE_ASSEMBLED")
        self.assertEqual(result["ready_scope_ids"], ["S1"])


if __name__ == "__main__":
    unittest.main()
