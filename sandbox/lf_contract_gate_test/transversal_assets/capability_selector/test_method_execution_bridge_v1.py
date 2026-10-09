#!/usr/bin/env python3
"""Negative and positive tests for the non-authority method execution bridge."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
SELECTOR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
REGISTRY = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v2.json"
sys.path.insert(0, str(SELECTOR))
from capability_selector_v3 import compose_capabilities_v3, replan_composition
from method_execution_bridge_v1 import execute_method_selection, _sha

REG = json.loads(REGISTRY.read_text())
CATALOG = [
    {"capability_code": "PACK_VALIDATION_HARNESS", "signal_type": "complexity",
     "accepted_values": ["HIGH"], "rank": 10, "state": "AVAILABLE"}
]
POLICY = {"fallback_capabilities": ["PACK_VALIDATION_HARNESS"]}


def verified(value):
    return {"value": value, "verification_state": "VERIFIED",
            "evidence_refs": ["fixture://verified-precondition"]}


def fixture():
    """Synthetic/test-only registry: DO NOT replace the authority's disabled registry."""
    reg = copy.deepcopy(REG)
    reg["execution_permission"] = True
    pre = {
        "evidence_sufficiency": verified("SUFFICIENT"),
        "candidate_exists": verified(True),
        "grader_available": verified(True),
        "deterministic_verifier_exists": verified(True),
    }
    context = {"causal_requirement": "HIGH", "selection_cycle": 0,
               "budget": {"max_method_cost_points": 10}}
    chosen = compose_capabilities_v3(context, CATALOG, POLICY, reg, pre)
    assert [x["method_id"] for x in chosen["selected_methods"]] == ["CAUSAL_ANALYSIS"]
    permitted = {"scope": "TEST_NON_AUTHORITY", "execution_id": "EXEC-SYNTH-001",
                 "receipt_ref": "fixture://test-scoped-permission",
                 "allowed_method_ids": ["CAUSAL_ANALYSIS", "SELF_REFINE", "VERIFIER_GUIDED_SEARCH", "REASONING_COMPOSITION_SEARCH"]}
    calls = []
    def handler(payload):
        calls.append(payload)
        return {"verification_state": "VERIFIED",
                "refuted_alternative": payload["alternative"],
                "verified_evidence": payload["source"]}
    binding = {"CAUSAL_ANALYSIS": {
        "scope": "TEST_NON_AUTHORITY",
        "handler": handler, "executor_id": "SYNTHETIC-CAUSAL-HANDLER",
        "execution_contract_ref": "fixture://explicit-test-only-contract",
        "source_revision": "TEST-REVISION-NON-AUTHORITY",
    }}
    data = {"CAUSAL_ANALYSIS": {"alternative": "stale-cache",
                                "source": "fixture://current-authority-readback"}}
    defaults = {
        "execution_id": "EXEC-SYNTH-001", "scope": "TEST_NON_AUTHORITY",
        "evidence_refs": ["fixture://evidence"], "permission_receipt": permitted,
        "verify_permission": lambda r: r == permitted,
        "verify_selection": lambda r: _sha(r) == _sha(chosen),
        "verify_result": lambda mid, inp, out: (
            mid == "CAUSAL_ANALYSIS" and
            out.get("refuted_alternative") == inp.get("alternative") and
            out.get("verified_evidence") == inp.get("source")),
        "result_verifier_id": "SYNTHETIC-SEPARATE-RESULT-VERIFIER",
    }
    return reg, chosen, binding, data, defaults, calls, pre, context


def run():
    total = 0
    reg, chosen, binding, data, options, calls, pre, context = fixture()
    def invoke(selection=chosen, registry=reg, bindings=binding, inputs=data, **updates):
        return execute_method_selection(
            selection, registry, bindings, inputs, **{**options, **updates})

    result = invoke()
    assert result["status"] == "EXECUTED_TEST_ONLY"
    assert result["actual_method_invocations"] == 1 and len(calls) == 1
    receipt = result["invocations"][0]
    assert receipt["method_id"] == "CAUSAL_ANALYSIS"
    assert receipt["result_state"] == "EXECUTED_VERIFIED"
    assert receipt["observed_wall_ms"] >= 0 and len(receipt["receipt_sha256"]) == 64
    assert not result["production_authorized"] and not result["cutover_eligible"]
    total += 1

    before = len(calls)
    r = invoke(registry=REG)
    assert r["status"] == "BLOCKED" and "REGISTRY_EXECUTION_PERMISSION_NOT_GRANTED" in r["blocking_codes"]
    assert len(calls) == before
    total += 1

    r = invoke(bindings={})
    assert r["status"] == "BLOCKED" and "METHOD_EXECUTOR_NOT_BOUND" in r["blocking_codes"] and len(calls)==before
    total += 1

    r = invoke(verify_permission=None)
    assert "INDEPENDENT_PERMISSION_VERIFIER_REQUIRED" in r["blocking_codes"] and len(calls)==before
    total += 1

    r = invoke(permission_receipt={**options["permission_receipt"],"execution_id":"another"})
    assert "PERMISSION_SCOPE_OR_EXECUTION_MISMATCH" in r["blocking_codes"] and len(calls)==before
    total += 1

    r = invoke(verify_permission=lambda _: False)
    assert "PERMISSION_NOT_INDEPENDENTLY_VERIFIED" in r["blocking_codes"] and len(calls)==before
    total += 1

    r = invoke(verify_selection=None)
    assert "INDEPENDENT_SELECTION_VERIFIER_REQUIRED" in r["blocking_codes"] and len(calls)==before
    total += 1

    bad = copy.deepcopy(chosen)
    bad["execution_authorized"] = True
    r = invoke(selection=bad)
    assert "SELECTOR_MUST_NOT_SELF_AUTHORIZE" in r["blocking_codes"] and len(calls)==before
    total += 1

    bad = copy.deepcopy(chosen)
    bad["selected_methods"][0]["precondition_receipt"]["status"]="UNKNOWN"
    r = invoke(selection=bad)
    assert "SELECTION_NOT_INDEPENDENTLY_VERIFIED" in r["blocking_codes"] and len(calls)==before
    total += 1

    r = invoke(verify_result=lambda *_: False)
    assert r["status"]=="METHOD_FAILED" and r["invocations"][0]["result_state"]=="EXECUTED_FAILED"
    total += 1

    def raise_failure(_):
        raise RuntimeError("synthetic handler failure")
    bad_binding = copy.deepcopy(binding)
    bad_binding["CAUSAL_ANALYSIS"]["handler"] = raise_failure
    r = invoke(bindings=bad_binding)
    assert r["status"]=="METHOD_FAILED" and r["actual_method_invocations"] == 1
    assert r["invocations"][0]["result_state"]=="EXECUTED_FAILED"
    total += 1

    experimental = copy.deepcopy(chosen)
    experimental["selected_methods"][0]["method_id"] = "REASONING_COMPOSITION_SEARCH"
    experimental["selected_methods"][0]["precondition_receipt"]["method_id"] = "REASONING_COMPOSITION_SEARCH"
    experimental["selected_methods"][0]["availability_state"] = "EXPERIMENTAL_NOT_ADMITTED"
    r = invoke(selection=experimental, verify_selection=lambda _: True)
    assert "METHOD_NOT_EXECUTION_ELIGIBLE" in r["blocking_codes"]
    total += 1

    wrong = copy.deepcopy(binding)
    wrong["CAUSAL_ANALYSIS"]["scope"]="PRODUCTION"
    r=invoke(bindings=wrong)
    assert "METHOD_BINDING_SCOPE_MISMATCH" in r["blocking_codes"]
    total += 1

    r=invoke(scope="PRODUCTION")
    assert "RUNTIME_SCOPE_NOT_SUPPORTED" in r["blocking_codes"]
    total += 1

    empty = compose_capabilities_v3({"risk":"LOW"}, CATALOG, POLICY, reg, {})
    assert not empty["selected_methods"]
    r=invoke(selection=empty, verify_selection=lambda v: _sha(v)==_sha(empty))
    assert r["status"]=="NO_METHOD_REQUIRED" and r["actual_method_invocations"]==0
    total += 1

    selection2 = compose_capabilities_v3(
        {"complexity": "HIGH"}, CATALOG, POLICY, reg, pre)
    assert {x["method_id"] for x in selection2["selected_methods"]}=={"SELF_REFINE","VERIFIER_GUIDED_SEARCH"}
    # No partial invocation if a later method is unbound.
    r=invoke(selection=selection2, verify_selection=lambda v: _sha(v)==_sha(selection2))
    assert r["status"]=="BLOCKED" and r["actual_method_invocations"]==0
    total += 1

    rerouted = replan_composition(
        {"complexity":"HIGH", "selection_cycle":0},
        {"trigger":"METHOD_FAILED", "method_id":"SELF_REFINE",
         "evidence_refs":["fixture://failed-method"]},
        CATALOG, POLICY, reg, pre)
    assert rerouted["status"]=="REPLANNED" and "SELF_REFINE" in rerouted["blocked_methods_for_current_run"]
    assert {x["method_id"] for x in rerouted["new_composition"]["selected_methods"]}=={"VERIFIER_GUIDED_SEARCH"}
    total += 1

    no_replan = replan_composition(
        context, {"trigger":"METHOD_FAILED", "method_id":"CAUSAL_ANALYSIS",
                  "evidence_refs":[]},
        CATALOG,POLICY,reg,pre)
    assert no_replan["status"] == "BLOCKED"
    total += 1

    denied_scope = copy.deepcopy(options["permission_receipt"])
    denied_scope["allowed_method_ids"] = ["SELF_REFINE"]
    r=invoke(permission_receipt=denied_scope, verify_permission=lambda x:x==denied_scope)
    assert "PERMISSION_METHOD_NOT_ALLOWED" in r["blocking_codes"]
    total += 1

    no_verified_evidence = compose_capabilities_v3(
        {"causal_requirement": "HIGH"}, CATALOG, POLICY, reg, {})
    assert not no_verified_evidence["selected_methods"]
    assert no_verified_evidence["rejected_methods"]
    r=invoke(selection=no_verified_evidence,
             verify_selection=lambda v: _sha(v)==_sha(no_verified_evidence))
    assert "METHODS_REJECTED_NO_ELIGIBLE_EXECUTION" in r["blocking_codes"]
    total += 1

    unresolved = copy.deepcopy(empty)
    unresolved["fallback_state"] = "CONTRADICTORY"
    r=invoke(selection=unresolved, verify_selection=lambda v: _sha(v)==_sha(unresolved))
    assert "SELECTOR_UNRESOLVED" in r["blocking_codes"]
    total += 1

    print(f"PASS_METHOD_EXECUTION_BRIDGE_V1 checks={total} synthetic_invocations=3 "
          "production_invocations=0 real_registry_permission=false cutover=false")
    return total


if __name__ == "__main__":
    run()
