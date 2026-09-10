#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

import input_governance_capability_resolver_v1 as capability
import input_governance_preexecution_facade_v1 as facade

ROOT = Path(__file__).resolve().parent
REGISTRY = capability.load_registry(ROOT / "input_governance_capability_registry_v1.json")


def entry(capability_id: str) -> dict:
    return next(x for x in REGISTRY["entries"] if x["capability_id"] == capability_id)


def currentness(capability_id: str) -> dict:
    e = entry(capability_id)
    state = {"state": "CURRENT"}
    if e["implementation_sha"] == "LIVE_FUNCTION_IDENTITY":
        state["implementation_ref"] = e["implementation_ref"]
    else:
        state["implementation_sha"] = e["implementation_sha"]
    return {capability_id: state}


def executor_for(capability_id: str, callback, *, override_sha: str | None = None) -> dict:
    e = entry(capability_id)
    bound = facade.BoundExecutor(
        implementation_ref=e["implementation_ref"],
        implementation_sha=override_sha if override_sha is not None else e["implementation_sha"],
        execute=callback,
    )
    return {e["implementation_ref"]: bound}


def attested(capability_id: str, **payload):
    e = entry(capability_id)
    return {
        **payload,
        "attestation": {
            "implementation_ref": e["implementation_ref"],
            "implementation_sha": e["implementation_sha"],
            "model_calls": payload.pop("model_calls", 0) if "model_calls" in payload else 0,
        },
    }


class FacadeTests(unittest.TestCase):
    def test_01_registered_read_positive_and_model_zero(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        calls = []
        def run(payload, plan):
            calls.append((payload, plan))
            return attested(cid, readback={"rows": [{"id": 221}]})
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","payload":{"source_key":"INPUT_GOVERNANCE"}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["status"], "PASS")
        self.assertTrue(result["backend_executed"])
        self.assertEqual(len(calls), 1)
        self.assertEqual(result["executor_attestation"]["model_calls"], 0)

    def test_02_registered_read_model_call_is_blocked(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        def run(payload, plan):
            e = entry(cid)
            return {"readback": {}, "attestation":{"implementation_ref":e["implementation_ref"],"implementation_sha":e["implementation_sha"],"model_calls":1}}
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","payload":{"source_key":"INPUT_GOVERNANCE"}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["code"], "BLOCK_REGISTERED_READ_MODEL_CALL")
        self.assertTrue(result["backend_executed"])

    def test_03_unknown_source_schema_positive(self):
        cid = "LF_SCHEMA_CONTRACT_RESOLUTION"
        def run(payload, plan): return attested(cid, schema_receipt={"object_identity":"public.example","state":"CURRENT"})
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"UNKNOWN_DATA_SOURCE_SCHEMA","consumer":"S33_CAPABILITY_RESOLVER","payload":{"object_identity":"public.example"}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["status"], "PASS")
        self.assertIn("schema_receipt", result["output"])

    def test_04_unknown_source_without_schema_receipt_blocks(self):
        cid = "LF_SCHEMA_CONTRACT_RESOLUTION"
        def run(payload, plan): return attested(cid, note="no receipt")
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"UNKNOWN_DATA_SOURCE_SCHEMA","consumer":"S33_CAPABILITY_RESOLVER","payload":{"object_identity":"public.example"}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["code"], "BLOCK_SCHEMA_RECEIPT_MISSING")

    def test_05_execution_authority_positive(self):
        cid = "LF_EXECUTION_AUTHORITY"
        def run(payload, plan): return attested(cid, authority_decision={"authority":"DETERMINISTIC","model_call_allowed":False})
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"EXECUTION_AUTHORITY_DECISION","consumer":"S33_CAPABILITY_RESOLVER","payload":{"category":"KNOWN_STRUCTURE"}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["output"]["authority_decision"]["authority"], "DETERMINISTIC")

    def test_06_dispatch_positive_live_identity(self):
        cid = "INPUT_GOVERNANCE_DISPATCH"
        def run(payload, plan): return attested(cid, dispatch_result={"action":"REUSE_CURRENT_RUN","run_id":221})
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"INPUT_GOVERNANCE_DISPATCH","consumer":"CONTRACT_ALLOWLIST_ONLY","payload":{"pantalla_id":43,"consumer":"CONTEXT_PACK"}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["output"]["dispatch_result"]["run_id"], 221)

    def test_07_pre_executor_sha_mismatch_blocks_before_backend(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        calls = []
        def run(payload, plan): calls.append(1); return attested(cid)
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","payload":{}},
            currentness=currentness(cid), executors=executor_for(cid, run, override_sha="0" * 40),
        )
        self.assertEqual(result["code"], "BLOCK_PRE_EXECUTOR_PROVENANCE_MISMATCH")
        self.assertFalse(result["backend_executed"])
        self.assertEqual(calls, [])

    def test_08_post_executor_attestation_mismatch_blocks(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        def run(payload, plan):
            e = entry(cid)
            return {"attestation":{"implementation_ref":e["implementation_ref"],"implementation_sha":"0" * 40,"model_calls":0}}
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","payload":{}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["code"], "BLOCK_POST_EXECUTOR_PROVENANCE_MISMATCH")
        self.assertTrue(result["backend_executed"])

    def test_09_missing_bound_executor_blocks_before_backend(self):
        cid = "LF_EXECUTION_AUTHORITY"
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"EXECUTION_AUTHORITY_DECISION","consumer":"S33_CAPABILITY_RESOLVER","payload":{}},
            currentness=currentness(cid), executors={},
        )
        self.assertEqual(result["code"], "BLOCK_BOUND_EXECUTOR_MISSING")
        self.assertFalse(result["backend_executed"])

    def test_10_stale_capability_blocks_before_backend(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        calls = []
        def run(payload, plan): calls.append(1); return attested(cid)
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","payload":{}},
            currentness={cid:{"state":"STALE","implementation_sha":entry(cid)["implementation_sha"]}},
            executors=executor_for(cid, run),
        )
        self.assertEqual(result["code"], "RERESOLVE_CAPABILITY_STALE")
        self.assertFalse(result["backend_executed"])
        self.assertEqual(calls, [])

    def test_11_model_selector_blocks_before_backend(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        calls = []
        def run(payload, plan): calls.append(1); return attested(cid)
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","resource_selector_authority":"MODEL","payload":{}},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["code"], "BLOCK_MODEL_RESOURCE_SELECTION")
        self.assertEqual(calls, [])

    def test_12_invalid_payload_blocks_before_backend(self):
        cid = "LF_BUDGETED_DATA_ACCESS"
        calls = []
        def run(payload, plan): calls.append(1); return attested(cid)
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"REGISTERED_DATA_READ","consumer":"S33_CAPABILITY_RESOLVER","payload":"raw sql"},
            currentness=currentness(cid), executors=executor_for(cid, run),
        )
        self.assertEqual(result["code"], "BLOCK_PAYLOAD_INVALID")
        self.assertFalse(result["backend_executed"])
        self.assertEqual(calls, [])

    def test_13_unknown_operation_blocks_before_resolution(self):
        result = facade.execute_preexecution(
            REGISTRY,
            {"operation_kind":"ARBITRARY_SQL","consumer":"S33_CAPABILITY_RESOLVER","payload":{}},
            currentness={}, executors={},
        )
        self.assertEqual(result["code"], "BLOCK_OPERATION_KIND_UNKNOWN")
        self.assertFalse(result["backend_executed"])


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(FacadeTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"S33_PREEXECUTION_FACADE_TESTS {'PASS' if result.wasSuccessful() else 'FAIL'} {result.testsRun}/13")
    raise SystemExit(0 if result.wasSuccessful() else 1)
