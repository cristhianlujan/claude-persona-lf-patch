"""Local synthetic candidate tests. No operational qualification or DB access."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import unittest
from types import SimpleNamespace

from programming_pg01_receiver_v1 import ReadOnlyReceiver, ExpectedHandoff, canonical_sha256
from programming_pg01_preplanning_checks_v1 import (
    DIMENSIONS, MAP_SCHEMA, DECISION_SCHEMA,
    validate_sufficiency, validate_technical_framework,
)

HERE = Path(__file__).resolve().parent


class PreplanningChecks(unittest.TestCase):
    def setUp(self):
        self.snapshot = json.loads((HERE / "fixtures/programming_pg01_receiver_base_v1.json").read_text())["context"]["extensions"]["programming_context_snapshot"]
        self.repo = "fixture/product"
        self.project = "fixture://project"
        self.store = {}
        self.frame = {"target_repo": self.repo, "project_ref": self.project,
                      "optimization_mode": "STANDARD",
                      "request_budget": {"amount": "1.00", "currency": "USD", "spent": "0.00"}}
        documents = {
            "standards_catalog": {"schema_version": "LF_STANDARDS_CATALOG_V1", "catalog_version": "fixture-1", "status": "SYNTHETIC_UNADMITTED"},
            "technical_profile": {"schema_version": "PG01_PROJECT_TECHNICAL_PROFILE_CANDIDATE_V1", "version": "fixture-1", "project_ref": self.project, "target_repo": self.repo, "namespace": "fixture_project", "rule_codes": [], "use_catalog_defaults": True},
            "control_mechanism": {"schema_version": "PG01_CONTROL_MECHANISM_CANDIDATE_V1", "version": "fixture-1", "target_repo": self.repo, "kind": "PRODUCT_PIPELINE", "control_refs": ["fixture://ci"]},
            "architecture_profile": "Synthetic architecture only",
            "consumption_policy": {"policy_version": "fixture-1", "modes": {"STANDARD": {"difficulty_model_routing": False, "controls": {"standards": True, "reviews": True, "tests": True}}}, "budget": {"amount": "1.00", "currency": "USD", "warning_percent": 80, "decision_percent": 100}},
        }
        for key, data in documents.items():
            self.pin(key, data)

    def pin(self, key, data):
        raw = data.encode() if isinstance(data, str) else json.dumps(data, sort_keys=True).encode()
        pin = {"repo": self.repo, "commit": "a"*40, "path": key + ".json", "sha256": hashlib.sha256(raw).hexdigest(), "version": "fixture-1"}
        if key == "architecture_profile":
            pin.update(project_ref=self.project, applies_to_repos=[self.repo])
        self.frame[key] = pin
        self.store[pin["path"]] = raw

    def c4(self, reader=None):
        return validate_technical_framework(self.frame, self.repo, reader or (lambda p: self.store[p["path"]]))

    def complete_c7(self, disposition="APPLICABLE"):
        data = {
            "messages": {"text": "Fixture exact copy"},
            "errors": {"code": "FIXTURE_ERROR", "text": "Fixture exact error"},
            "navigation": {"event_code": "FIXTURE_VIEW"},
            "history": {"entity_ref": "fixture://entity", "requires_history": False},
            "consents": {"document_ref": "fixture://document", "document_version": "fixture-1", "document_state": "CURRENT"},
        }
        rows = []
        for dim in DIMENSIONS:
            item = {"canonical_ref": "fixture://material/" + dim, **data[dim]}
            rows.append({
                "binding_id": "fixture-" + dim, "scope_refs": ["S1"], "binding_kind": "FIXTURE_" + dim,
                "canonical_ref": "fixture://decision/" + dim, "currentness_ref": "fixture://current",
                "resolver_ref": "fixture://resolver", "evidence_refs": ["fixture://evidence"], "blockers": [],
                "implementation_obligation": "MUST_PRESERVE_EXACT",
                "value_transport": "INLINE_RESOLVED_VALUE_PLUS_CANONICAL_REF",
                "resolved_current_value": {"schema_version": DECISION_SCHEMA, "dimension": dim,
                    "requirement_ids": ["REQ1"], "reason": "Explicit synthetic decision", "disposition": disposition,
                    "items": [item] if disposition == "APPLICABLE" else []},
            })
        self.snapshot["implementability_schema"]["canonical_implementation_bindings"] = rows
        return self.mapping()

    def mapping(self):
        return {"schema_version": MAP_SCHEMA, "source_ref": "fixture://candidate-map",
                "snapshot_sha256": canonical_sha256(self.snapshot),
                "binding_kinds": {d: "FIXTURE_" + d for d in DIMENSIONS}}

    def c7(self):
        return validate_sufficiency(self.snapshot, ["S1"], self.mapping())

    def test_c4_complete_structure_never_admits(self):
        got = self.c4()
        self.assertEqual(got["status"], "COMPLETE")
        self.assertFalse(got["operational_admission"])
        self.assertFalse(got["execution_allowed"])
        self.assertEqual(got["catalog_status"], "SYNTHETIC_UNADMITTED")

    def test_c4_each_missing_component(self):
        original = deepcopy(self.frame)
        for key in ("standards_catalog", "technical_profile", "control_mechanism", "architecture_profile", "consumption_policy", "request_budget", "optimization_mode"):
            with self.subTest(key=key):
                self.frame = deepcopy(original)
                self.frame.pop(key)
                self.assertNotEqual(self.c4()["status"], "COMPLETE")

    def test_c4_digest_and_version(self):
        self.frame["standards_catalog"]["sha256"] = "0"*64
        self.assertEqual(self.c4()["status"], "MISSING")
        self.setUp()
        self.frame["standards_catalog"]["version"] = "OTHER"
        self.assertEqual(self.c4()["status"], "BLOCK")

    def test_c4_wrong_repo_namespace_and_rule_selection(self):
        self.frame["technical_profile"]["repo"] = "other/repo"
        self.assertEqual(self.c4()["status"], "BLOCK")
        for field, value in (("namespace", ""), ("use_catalog_defaults", False), ("target_repo", "other/repo")):
            self.setUp()
            doc = json.loads(self.store["technical_profile.json"]); doc[field] = value
            self.pin("technical_profile", doc)
            self.assertEqual(self.c4()["status"], "BLOCK")

    def test_c4_control_destination(self):
        doc = json.loads(self.store["control_mechanism.json"]); doc["kind"] = "LF_PLATFORM"
        self.pin("control_mechanism", doc)
        self.assertEqual(self.c4()["status"], "BLOCK")

    def test_c4_architecture_exact_pin(self):
        for field, value in (("commit", "main"), ("project_ref", "other"), ("applies_to_repos", []), ("path", "../outside")):
            self.setUp(); self.frame["architecture_profile"][field] = value
            self.assertNotEqual(self.c4()["status"], "COMPLETE")

    def test_c4_no_control_relaxation_or_model_routing(self):
        for key in ("standards", "reviews", "tests"):
            self.setUp()
            doc = json.loads(self.store["consumption_policy.json"]); doc["modes"]["STANDARD"]["controls"][key] = False
            self.pin("consumption_policy", doc)
            self.assertEqual(self.c4()["status"], "BLOCK")
        self.setUp()
        doc = json.loads(self.store["consumption_policy.json"]); doc["modes"]["STANDARD"]["difficulty_model_routing"] = True
        self.pin("consumption_policy", doc)
        self.assertEqual(self.c4()["status"], "BLOCK")

    def test_c4_measure_only_not_fake_budget(self):
        doc = json.loads(self.store["consumption_policy.json"]); doc["budget"]["amount"] = "POR_DEFINIR"
        self.pin("consumption_policy", doc)
        got = self.c4()
        self.assertEqual((got["status"], got["budget_state"]), ("MISSING", "MEASURE_ONLY"))
        self.assertEqual(got["issues"][0]["code"], "BUDGET_UNCONFIGURED_MEASURE_ONLY")

    def test_c4_budget_thresholds_and_invalid_numbers(self):
        for spent, status, state in (("0.79", "COMPLETE", "WITHIN_BUDGET"), ("0.80", "COMPLETE", "WARNING"), ("1.00", "REQUIRES_DECISION", "EXHAUSTED"), ("1.01", "REQUIRES_DECISION", "EXHAUSTED")):
            self.frame["request_budget"]["spent"] = spent
            got = self.c4(); self.assertEqual((got["status"], got["budget_state"]), (status, state))
        for spent in ("NaN", "Infinity", "-1", 0.0):
            self.frame["request_budget"]["spent"] = spent
            self.assertEqual(self.c4()["status"], "BLOCK")

    def test_c4_provider_exception_and_nonbytes(self):
        def unavailable(pin): raise RuntimeError("synthetic provider unavailable")
        self.assertEqual(self.c4(unavailable)["status"], "MISSING")
        self.assertEqual(self.c4(lambda p: {"CURRENT": True})["status"], "MISSING")

    def test_c7_old_fixture_is_missing_all_five(self):
        got = self.c7()
        self.assertEqual(got["status"], "MISSING")
        self.assertEqual(len(got["issues"]), 5)

    def test_c7_complete_and_deterministic_without_mutation(self):
        self.complete_c7()
        before = deepcopy(self.snapshot)
        got = self.c7()
        self.assertEqual(got["status"], "COMPLETE")
        self.assertFalse(got["operational_admission"])
        self.assertEqual(self.c7(), got)
        self.assertEqual(self.snapshot, before)

    def test_c7_explicit_not_applicable(self):
        self.complete_c7("NOT_APPLICABLE")
        self.assertEqual(self.c7()["status"], "COMPLETE")

    def test_c7_every_missing_dimension(self):
        self.complete_c7(); good = deepcopy(self.snapshot)
        for dimension in DIMENSIONS:
            self.snapshot = deepcopy(good)
            rows = self.snapshot["implementability_schema"]["canonical_implementation_bindings"]
            rows[:] = [r for r in rows if r["binding_kind"] != "FIXTURE_" + dimension]
            got = self.c7()
            self.assertEqual(got["status"], "MISSING")
            self.assertEqual(got["issues"][0]["path"], "S1." + dimension)

    def test_c7_empty_or_unresolved_is_not_not_applicable(self):
        for field, value in (("canonical_ref", ""), ("currentness_ref", ""), ("resolver_ref", ""), ("evidence_refs", []), ("blockers", ["PENDING"]), ("resolved_current_value", None), ("value_transport", "EXACT_REF_ONLY")):
            self.complete_c7()
            self.snapshot["implementability_schema"]["canonical_implementation_bindings"][0][field] = value
            self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_missing_material_values_and_demo(self):
        self.complete_c7()
        rows = self.snapshot["implementability_schema"]["canonical_implementation_bindings"]
        rows[0]["resolved_current_value"]["items"][0].pop("text")
        self.assertEqual(self.c7()["status"], "MISSING")
        self.complete_c7()
        self.snapshot["implementability_schema"]["canonical_implementation_bindings"][-1]["resolved_current_value"]["items"][0]["document_state"] = "DEMO"
        self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_wrong_context_map_or_scope(self):
        mapping = self.complete_c7()
        mapping["snapshot_sha256"] = "0"*64
        self.assertEqual(validate_sufficiency(self.snapshot, ["S1"], mapping)["status"], "MISSING")
        self.complete_c7()
        self.snapshot["implementability_schema"]["canonical_implementation_bindings"][0]["scope_refs"] = ["OTHER"]
        self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_requirement_coverage(self):
        self.complete_c7()
        self.snapshot["implementability_schema"]["canonical_implementation_bindings"][0]["resolved_current_value"]["requirement_ids"] = ["OTHER"]
        self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_conflicting_decisions(self):
        self.complete_c7()
        rows = self.snapshot["implementability_schema"]["canonical_implementation_bindings"]
        extra = deepcopy(rows[0]); extra["binding_id"] = "different"; extra["resolved_current_value"]["disposition"] = "NOT_APPLICABLE"; extra["resolved_current_value"]["items"] = []
        rows.append(extra)
        self.assertEqual(self.c7()["status"], "CONTRADICTION")

    def test_c7_independent_blocked_scope_and_dependency(self):
        self.complete_c7()
        self.snapshot["scope_readiness"].append({"scope_id": "S2", "status": "BLOCKED", "blockers": ["PENDING"], "depends_on_scope_ids": []})
        self.assertEqual(self.c7()["status"], "COMPLETE")
        self.snapshot["scope_readiness"][0]["depends_on_scope_ids"] = ["S2"]
        self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_no_map_or_bad_kind_map(self):
        self.assertEqual(validate_sufficiency(self.snapshot, ["S1"], None)["status"], "MISSING")
        mapping = self.mapping(); mapping["binding_kinds"]["errors"] = mapping["binding_kinds"]["messages"]
        self.assertEqual(validate_sufficiency(self.snapshot, ["S1"], mapping)["status"], "MISSING")

    def test_c7_declared_not_applicable_requires_reason(self):
        self.complete_c7("NOT_APPLICABLE")
        self.snapshot["implementability_schema"]["canonical_implementation_bindings"][0]["resolved_current_value"]["reason"] = ""
        self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_malformed_material_identities_fail_closed(self):
        for field, value in (("requirement_id", []), ("requirement_id", {}), ("scope_refs", True), ("scope_refs", 1)):
            self.setUp(); self.complete_c7()
            self.snapshot["implementability_schema"]["requirements"][0][field] = value
            self.assertEqual(self.c7()["status"], "MISSING")

    def test_c7_duplicate_requirement_or_scope(self):
        self.complete_c7()
        self.snapshot["implementability_schema"]["requirements"] *= 2
        self.assertEqual(self.c7()["status"], "CONTRADICTION")
        self.setUp(); self.complete_c7()
        self.snapshot["scope_readiness"] *= 2
        self.assertEqual(self.c7()["status"], "CONTRADICTION")

    def test_c4_architecture_scope_type(self):
        self.frame["architecture_profile"]["applies_to_repos"] = True
        self.assertEqual(self.c4()["status"], "BLOCK")

    def test_c4_duplicate_json_keys(self):
        raw = b'{"catalog_version":"fixture-1","catalog_version":"OTHER"}'
        self.frame["standards_catalog"]["sha256"] = hashlib.sha256(raw).hexdigest()
        self.store["standards_catalog.json"] = raw
        got = self.c4()
        self.assertEqual(got["status"], "MISSING")
        self.assertEqual(got["issues"][0]["code"], "DUPLICATE_JSON_KEY")

    def test_boundary_malformed_currentness_blocks(self):
        ctx = json.loads((HERE / "fixtures/programming_pg01_receiver_base_v1.json").read_text())["context"]
        for malformed in (None, [], "CURRENT", True, {"ready": True, "decision": "CURRENT"}, {"ready": True, "decision": "CURRENT", "bounded_validation_required": "true"}):
            with self.subTest(malformed=malformed):
                reader = SimpleNamespace(read=lambda e: {"resolution": {"state": "RESOLVED", "context_id": e.context_id, "context_sha256": e.context_sha256, "consumer_code": e.consumer_code, "subject_ref": e.subject_ref, "context": ctx}, "exact_receipt_valid": True, "snapshot_validation": {"state": "VALID"}})
                receiver = ReadOnlyReceiver(reader, SimpleNamespace(evaluate=lambda *args: malformed))
                expected = ExpectedHandoff("11111111-1111-1111-1111-111111111111", "a"*64, receiver.contract_digest, ctx["consumer_code"], ctx["subject"]["ref"], "2026-10-02T00:00:00Z")
                got = receiver.consume(expected, "S1")
                self.assertEqual(got["state"], "BLOCK")
                self.assertEqual(got["code"], "CURRENTNESS_RESULT_INVALID")
                self.assertEqual(got["receipt"]["verdict"], "BLOCK")


if __name__ == "__main__":
    unittest.main()
