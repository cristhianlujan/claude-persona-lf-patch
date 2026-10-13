#!/usr/bin/env python3
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
D = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
REGISTRY = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v2.json"
sys.path.insert(0, str(D))
from method_adaptive_loop_v1 import run_adaptive_method_loop

CATALOG = [{"capability_code": "PACK_VALIDATION_HARNESS",
            "signal_type": "complexity", "accepted_values": ["HIGH"],
            "rank": 10, "state": "AVAILABLE"}]
POLICY = {"fallback_capabilities": ["PACK_VALIDATION_HARNESS"]}


def verified(x):
    return {"value": x, "verification_state": "VERIFIED",
            "evidence_refs": ["fixture://precondition"]}


def run():
    base = json.loads(REGISTRY.read_text())
    reg = deepcopy(base)
    reg["execution_permission"] = True   # synthetic TEST_ONLY fixture, not real registry
    seen = []
    def fail_handler(payload):
        seen.append("SELF_REFINE")
        return {"verification_state": "REJECTED", "reason": "synthetic-plateau"}
    def verifier(payload):
        seen.append("VERIFIER_GUIDED_SEARCH")
        return {"verification_state": "VERIFIED", "reason": "verified-via-synthetic-oracle"}
    bindings = {
        mid: {"scope": "TEST_NON_AUTHORITY", "handler": handler,
              "executor_id": "FIXTURE-" + mid, "source_revision": "SYNTHETIC-V1",
              "execution_contract_ref": "fixture://method-exec-contract"}
        for mid, handler in (
            ("SELF_REFINE", fail_handler),
            ("VERIFIER_GUIDED_SEARCH", verifier),
        )
    }
    permitted = {
        "scope": "TEST_NON_AUTHORITY", "execution_id": "EXEC-FIXTURE-REPLAN",
        "allowed_method_ids": list(bindings),
        "receipt_ref": "fixture://independent-permission"
    }
    kwargs = {
        "context": {"complexity": "HIGH", "selection_cycle": 0,
                    "budget": {"max_method_cost_points": 10}},
        "catalog": CATALOG, "capability_policy": POLICY, "registry": reg,
        "precondition_state": {
            "candidate_exists": verified(True), "grader_available": verified(True),
            "deterministic_verifier_exists": verified(True)},
        "bindings": bindings, "method_inputs": {mid: {"payload": "test"} for mid in bindings},
        "execution_id": "EXEC-FIXTURE-REPLAN",
        "evidence_refs": ["fixture://task-001"],
        "permission_receipt": permitted,
        "verify_permission": lambda x: x == permitted,
        "verify_selection": lambda sel: sel.get("schema") == "CAPABILITY_SELECTOR_COMPOSITION_V3"
            and not sel.get("execution_authorized") and
            all(x.get("precondition_receipt", {}).get("status") == "PASS"
                for x in sel.get("selected_methods", [])),
        "verify_result": lambda mid, data, response: response.get("verification_state") == "VERIFIED",
        "result_verifier_id": "INDEPENDENT-FIXTURE-VERIFIER",
        "observation_evidence_refs": ["fixture://method-failure"],
    }
    ok = run_adaptive_method_loop(**kwargs)
    assert ok["status"] == "COMPLETED_TEST_ONLY",ok
    assert ok["actual_invocations"] == 2 and len(ok["cycles"]) == 2
    assert seen == ["SELF_REFINE", "VERIFIER_GUIDED_SEARCH"]
    assert ok["cycles"][0]["replan"]["status"] == "REPLANNED"
    assert ok["cycles"][1]["selected_method_ids"] == ["VERIFIER_GUIDED_SEARCH"]
    assert not ok["production_authorized"] and not ok["cutover_eligible"]
    checks = 1

    seen.clear()
    denied = run_adaptive_method_loop(**{**kwargs, "registry": base})
    assert denied["status"] == "BLOCKED"
    assert "REGISTRY_EXECUTION_PERMISSION_NOT_GRANTED" in denied["blocking_codes"]
    assert seen == []
    checks += 1

    seen.clear()
    no_replan = run_adaptive_method_loop(**{**kwargs, "observation_evidence_refs": []})
    assert no_replan["status"] == "BLOCKED"
    assert "REPLAN_EVIDENCE_REQUIRED" in no_replan["blocking_codes"]
    assert seen == ["SELF_REFINE"]
    checks += 1

    seen.clear()
    one_cycle = run_adaptive_method_loop(**{**kwargs, "max_cycles": 1})
    assert one_cycle["status"] == "STOP_ITERATION_BUDGET"
    assert len(one_cycle["cycles"]) == 1 and seen == ["SELF_REFINE"]
    checks += 1

    seen.clear()
    invalid = run_adaptive_method_loop(**{**kwargs, "max_cycles": 0})
    assert invalid["status"] == "BLOCKED" and seen == []
    checks += 1

    seen.clear()
    no_method = run_adaptive_method_loop(**{**kwargs, "context": {"risk": "LOW"}})
    assert no_method["status"] == "COMPLETED_TEST_ONLY"
    assert no_method["actual_invocations"] == 0 and seen == []
    checks += 1

    print(f"PASS_ADAPTIVE_METHOD_LOOP_V1 checks={checks} "
          "synthetic_replan_cycles=2 production_invocations=0 no_cutover=true")


if __name__ == "__main__":
    run()
