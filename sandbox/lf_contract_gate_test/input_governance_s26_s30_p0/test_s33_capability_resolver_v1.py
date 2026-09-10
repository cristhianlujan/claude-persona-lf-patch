#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

import input_governance_capability_resolver_v1 as subject

ROOT = Path(__file__).resolve().parent
REGISTRY_PATH = ROOT / "input_governance_capability_registry_v1.json"


def current_for(entry: dict) -> dict:
    current = {"state": "CURRENT"}
    if entry["implementation_sha"] == "LIVE_FUNCTION_IDENTITY":
        current["implementation_ref"] = entry["implementation_ref"]
    else:
        current["implementation_sha"] = entry["implementation_sha"]
    return current


class CapabilityResolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry = subject.load_registry(REGISTRY_PATH)

    def entry(self, capability_id: str) -> dict:
        return next(x for x in self.registry["entries"] if x["capability_id"] == capability_id)

    def test_01_registry_exact_blob_and_schema_valid(self):
        raw = REGISTRY_PATH.read_bytes()
        checked = subject.validate_registry(
            self.registry,
            expected_blob_sha=subject.EXPECTED_REGISTRY_BLOB_SHA,
            raw_bytes=raw,
        )
        self.assertTrue(checked["valid"], checked)
        self.assertEqual(checked["entry_count"], 17)

    def test_02_external_edge_capability_resolves(self):
        entry = self.entry("INPUT_GOVERNANCE_ORCHESTRATE")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="GOVERNED_SERVICE_CALLER",
            currentness=current_for(entry),
        )
        self.assertEqual(result["status"], subject.PASS)
        self.assertEqual(result["code"], "CAPABILITY_RESOLVED")
        self.assertEqual(result["execution_plan"]["implementation_sha"], entry["implementation_sha"])

    def test_03_s30_typed_data_access_resolves_by_exact_sha(self):
        entry = self.entry("LF_TYPED_DATA_ACCESS")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="S33_CAPABILITY_RESOLVER",
            currentness=current_for(entry),
        )
        self.assertEqual(result["status"], subject.PASS)
        self.assertEqual(result["execution_plan"]["owner_lane"], "S30-B")
        self.assertEqual(result["execution_plan"]["implementation_sha"], "0fc3792e2f75fd5befc6fb22eb6d8e53ccd16965")

    def test_04_live_rpc_uses_identity_binding(self):
        entry = self.entry("INPUT_GOVERNANCE_DISPATCH")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="CONTRACT_ALLOWLIST_ONLY",
            currentness=current_for(entry),
        )
        self.assertEqual(result["status"], subject.PASS)
        self.assertEqual(result["execution_plan"]["implementation_ref"], entry["implementation_ref"])

    def test_05_unknown_capability_routes_to_discovery(self):
        result = subject.resolve_capability(
            self.registry,
            capability_id="FUTURE_UNKNOWN_CAPABILITY",
            consumer="S33_CAPABILITY_RESOLVER",
            currentness={"state": "CURRENT"},
        )
        self.assertEqual(result["status"], subject.DISCOVERY)
        self.assertEqual(result["code"], "DISCOVERY_OR_SCHEMA_RESOLVER")

    def test_06_raw_function_name_is_denied_before_discovery(self):
        result = subject.resolve_capability(
            self.registry,
            capability_id="programacion.fn_input_governance_execute",
            consumer="CONTRACT_ALLOWLIST_ONLY",
            currentness={"state": "CURRENT"},
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_RAW_RESOURCE_NAME_SELECTION")

    def test_07_model_cannot_select_resource(self):
        entry = self.entry("LF_TYPED_DATA_ACCESS")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="S33_CAPABILITY_RESOLVER",
            currentness=current_for(entry),
            selector_authority="MODEL",
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_MODEL_RESOURCE_SELECTION")

    def test_08_consumer_mismatch_is_fail_closed(self):
        entry = self.entry("INPUT_GOVERNANCE_VALIDATE")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="UNAUTHORIZED_CALLER",
            currentness=current_for(entry),
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_CONSUMER_NOT_ALLOWED")

    def test_09_stale_digest_requires_reresolve(self):
        entry = self.entry("INPUT_GOVERNANCE_ORCHESTRATE")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="GOVERNED_SERVICE_CALLER",
            currentness={"state":"CURRENT","implementation_sha":"0" * 64},
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "RERESOLVE_CAPABILITY_STALE")

    def test_10_deprecated_capability_is_denied(self):
        registry = copy.deepcopy(self.registry)
        entry = next(x for x in registry["entries"] if x["capability_id"] == "INPUT_GOVERNANCE_ORCHESTRATE")
        entry["deprecated"] = True
        result = subject.resolve_capability(
            registry,
            capability_id=entry["capability_id"],
            consumer="GOVERNED_SERVICE_CALLER",
            currentness=current_for(entry),
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_CAPABILITY_DEPRECATED")

    def test_11_multiple_current_implementations_are_ambiguous(self):
        registry = copy.deepcopy(self.registry)
        original = next(x for x in registry["entries"] if x["capability_id"] == "LF_TYPED_DATA_ACCESS")
        duplicate = copy.deepcopy(original)
        duplicate["implementation_ref"] = "sandbox/independent_duplicate/lf_data_access.py"
        registry["entries"].append(duplicate)
        result = subject.resolve_capability(
            registry,
            capability_id="LF_TYPED_DATA_ACCESS",
            consumer="S33_CAPABILITY_RESOLVER",
            currentness=current_for(original),
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_CAPABILITY_AMBIGUOUS")
        self.assertEqual(result["candidate_count"], 2)

    def test_12_internal_nonselectable_capability_is_denied(self):
        entry = self.entry("INPUT_CURRENTNESS")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="INPUT_GOVERNANCE_INTERNAL",
            currentness=current_for(entry),
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_CAPABILITY_NOT_SELECTABLE")

    def test_13_contract_drift_blocks_even_internal_resolution(self):
        entry = self.entry("INPUT_CONTEXT_JIT")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="INPUT_GOVERNANCE_INTERNAL",
            currentness=current_for(entry),
            allow_internal=True,
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "BLOCK_CAPABILITY_CONTRACT_DRIFT")

    def test_14_missing_required_registry_field_is_detected(self):
        registry = copy.deepcopy(self.registry)
        del registry["entries"][0]["authority"]
        checked = subject.validate_registry(registry)
        self.assertFalse(checked["valid"])
        self.assertIn("ENTRY_REQUIRED_FIELD_MISSING", checked["blocking_codes"])

    def test_15_missing_currentness_is_fail_closed(self):
        entry = self.entry("LF_EXECUTION_AUTHORITY")
        result = subject.resolve_capability(
            self.registry,
            capability_id=entry["capability_id"],
            consumer="S33_CAPABILITY_RESOLVER",
            currentness=None,
        )
        self.assertEqual(result["status"], subject.BLOCKED)
        self.assertEqual(result["code"], "RERESOLVE_CAPABILITY_STALE")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CapabilityResolverTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"S33_CAPABILITY_RESOLVER_TESTS {'PASS' if result.wasSuccessful() else 'FAIL'} {result.testsRun}/15")
    raise SystemExit(0 if result.wasSuccessful() else 1)
