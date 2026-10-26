"""Technical currentness adapter cases; real engine, synthetic material provider."""
from copy import deepcopy
from types import SimpleNamespace
import subprocess
import unittest

import test_programming_pg01_preplanning_receiver_v1 as integration_cases
from programming_pg01_receiver_v1 import CanonicalCurrentnessPort, ROOT, canonical_sha256
from lf_currentness_authority_v1 import compatibility_proof_sha256


def change_material(packet, material_id, change_class):
    binding = packet["binding"]
    row = next(m for m in binding["materials"] if m["material_id"] == material_id)
    row["current_digest"] = "0"*64
    binding["compatibility_contract"]["assessments"] = [{
        "material_id": material_id, "change_class": change_class,
        "proof_sha256": compatibility_proof_sha256(
            material_id=material_id, change_class=change_class,
            bound_fingerprint=row["bound_digest"], current_fingerprint=row["current_digest"],
            contract_identity=binding["contract_identity"],
            implementation_binding=binding["implementation_binding"]),
    }]


class TechnicalCurrentnessChecks(unittest.TestCase):
    def setUp(self):
        self.case = integration_cases.IntegratedReceiverChecks()
        self.case.setUp()

    def run_case(self, mutate=None, port=None):
        wrapper = self.case.receiver()
        wrapper._technical_currentness = port or integration_cases.currentness_fixture(self.case.fixture, mutate)
        return wrapper.consume(self.case.expected, "S1")

    def assert_receipt_integrity(self, receipt):
        payload = deepcopy(receipt)
        digest = payload.pop("receipt_sha256")
        self.assertEqual(digest, canonical_sha256(payload))

    def test_real_engine_current_and_digest(self):
        got = self.run_case()
        currentness = got["technical_currentness"]
        self.assertEqual(currentness["decision"], "CURRENT")
        self.assert_receipt_integrity(currentness)
        self.assertEqual(got["material_projection"]["technical_currentness"], currentness)
        self.assertFalse(got["operational_admission"])

    def test_missing_technical_port_blocks(self):
        wrapper = self.case.receiver(); wrapper._technical_currentness = None
        got = wrapper.consume(self.case.expected, "S1")
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["technical_currentness"]["reason"], "TECHNICAL_CURRENTNESS_PORT_MISSING")
        self.assertEqual(got["receipt"]["verdict"], "BLOCK")

    def test_bad_provider_result_fails_closed(self):
        for malformed in (None, [], True, "CURRENT", {"ready": True}, {"ready":True,"decision":"CURRENT","bounded_validation_required":False}, float("nan")):
            port = SimpleNamespace(evaluate=lambda *a: malformed)
            got = self.run_case(port=port)
            self.assertEqual(got["state"], "BLOCK")

    def test_provider_exception_blocks(self):
        def fail(*args): raise RuntimeError("fixture")
        got = self.run_case(port=SimpleNamespace(evaluate=fail))
        self.assertEqual(got["technical_currentness"]["reason"], "TECHNICAL_CURRENTNESS_UNAVAILABLE")

    def test_subject_scope_target_and_material_fingerprint(self):
        for key, value in (("context_id", "OTHER"), ("context_sha256", "0"*64),
                           ("scope_id", "OTHER"), ("scope_ids", ["OTHER"]),
                           ("target", {}), ("technical_materials_sha256", "0"*64)):
            got = self.run_case(lambda p: p.update({key: value}))
            self.assertEqual(got["technical_currentness"]["reason"], "TECHNICAL_CURRENTNESS_SUBJECT_MISMATCH")
            self.assertEqual(got["state"], "BLOCK")

    def test_tampered_authority_receipt_is_rejected(self):
        original = integration_cases.currentness_fixture(self.case.fixture)
        def evaluate(*args):
            got = original.evaluate(*args)
            got["materials"]["technical_framework"]["current_fingerprint"] = "0"*64
            return got
        got = self.run_case(port=SimpleNamespace(evaluate=evaluate))
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["technical_currentness"]["reason"], "TECHNICAL_CURRENTNESS_UNAVAILABLE")

    def test_material_roots_cannot_be_hidden(self):
        got = self.run_case(lambda p: p["binding"].update(root_material_ids=["context"]))
        self.assertEqual(got["technical_currentness"]["reason"], "CURRENTNESS_ROOTS_INCOMPLETE")

    def test_unknown_dependencies_fail_closed(self):
        got = self.run_case(lambda p: p["binding"].update(dependency_completeness="UNKNOWN"))
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["technical_currentness"]["decision"], "UNKNOWN_FAIL_CLOSED")

    def test_duplicate_material_id_blocks(self):
        got = self.run_case(lambda p: p["binding"]["materials"].append(deepcopy(p["binding"]["materials"][-1])))
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["technical_currentness"]["reason"], "CURRENTNESS_ROOTS_INCOMPLETE")

    def test_wrong_bound_material_cannot_replace_pin(self):
        def alter(packet):
            packet["binding"]["materials"][-1]["bound_digest"] = "0"*64
        got = self.run_case(alter)
        self.assertEqual(got["state"], "BLOCK")
        self.assertTrue(got["technical_currentness"]["reason"].startswith("CURRENTNESS_MATERIAL_BINDING_MISMATCH:"))

    def test_changed_technical_artifact_blocks_even_compatible(self):
        got = self.run_case(lambda p: change_material(p, "technical_artifact:standards_catalog", "IMPLEMENTATION_ONLY_COMPATIBLE"))
        report = got["technical_currentness"]
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(report["reason"], "TECHNICAL_REVALIDATION_REQUIRED:technical_artifact:standards_catalog")
        self.assertNotIn("receipt_sha256", report)
        self.assertTrue(report["authority_receipt"]["ready"])
        self.assert_receipt_integrity(report["authority_receipt"])

    def test_changed_artifact_breaking_is_stale(self):
        got = self.run_case(lambda p: change_material(p, "technical_artifact:technical_profile", "BREAKING"))
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["technical_currentness"]["decision"], "STALE_AFFECTED")
        self.assert_receipt_integrity(got["technical_currentness"]["authority_receipt"])

    def test_pin_identity_change_requires_revalidation(self):
        got = self.run_case(lambda p: change_material(p, "technical_pin:architecture_profile", "IMPLEMENTATION_ONLY_COMPATIBLE"))
        self.assertEqual(got["state"], "BLOCK")
        self.assertTrue(got["technical_currentness"]["reason"].startswith("TECHNICAL_REVALIDATION_REQUIRED:"))

    def test_snapshot_rebuild_check_keeps_authority_receipt_intact(self):
        got = self.run_case(lambda p: change_material(p, "snapshot_authority", "IMPLEMENTATION_ONLY_COMPATIBLE"))
        self.assertEqual(got["technical_currentness"]["reason"], "SNAPSHOT_REBUILD_REQUIRED:snapshot_authority")
        self.assertNotIn("receipt_sha256", got["technical_currentness"])
        self.assert_receipt_integrity(got["technical_currentness"]["authority_receipt"])

    def test_unrelated_revision_drift_allows_rebound(self):
        previous = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD^"], text=True).strip()
        def alter(packet):
            packet["binding"]["authority"]["bound_revision"] = previous
            packet["binding"]["evidence_revision"] = previous
        got = self.run_case(alter)
        self.assertEqual(got["state"], "ACCEPT")
        self.assertEqual(got["technical_currentness"]["decision"], "CURRENT_REBOUND")
        self.assert_receipt_integrity(got["technical_currentness"])

    def test_pending_bounded_validation_cannot_be_bypassed(self):
        got = self.run_case(lambda p: change_material(p, "snapshot_source", "CONTRACT_COMPATIBLE"))
        self.assertEqual(got["state"], "BLOCK")
        self.assertIs(got["technical_currentness"]["bounded_validation_required"], True)

    def test_input_declared_current_is_not_authority(self):
        got = self.run_case(lambda p: p.update(ready=True, decision="CURRENT"))
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["technical_currentness"]["reason"], "TECHNICAL_CURRENTNESS_PACKET_INVALID")

    def test_incomplete_structure_never_queries_currentness(self):
        calls = []
        def evaluate(*args):
            calls.append(True)
            raise RuntimeError("should not be used")
        wrapper = self.case.receiver(lambda p: p.update(technical_framework=None))
        wrapper._technical_currentness = SimpleNamespace(evaluate=evaluate)
        got = wrapper.consume(self.case.expected, "S1")
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(calls, [])
        self.assertEqual(got["technical_currentness"]["reason"], "STRUCTURE_INCOMPLETE_NOT_EVALUATED")

    def test_adapter_cannot_override_snapshot_roots(self):
        port = CanonicalCurrentnessPort(ROOT, lambda e,s: {
            "context_id":e.context_id, "context_sha256":e.context_sha256, "scope_id":s,
            "binding":{}})
        got = port.evaluate(self.case.expected, self.case.fixture.snapshot, "S1",
                            additional_materials={"context":"0"*64})
        self.assertEqual(got["reason"], "ADDITIONAL_MATERIALS_INVALID")


if __name__ == "__main__":
    unittest.main()
