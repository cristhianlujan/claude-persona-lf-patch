"""Atomic registry-driven offline argument mapping checks (no algorithm calls)."""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
from profile_math_payload_binding_v1 import prepare_math_arguments

ROOT = Path(__file__).resolve().parents[3]
REG = json.loads((ROOT / "sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v2.json").read_text())


def run() -> int:
    signatures = {
        "CAUSAL_GRAPH_ANALYSIS": ["nodes", "edges", "start", "end"],
        "OCHIAI_SUSPICIOUSNESS": ["cases", "suspects"],
        "RECIPROCAL_RANK_FUSION": ["sources"],
        "DELTA_DEBUGGING": ["atoms"],
        "MCNEMAR_AND_CONFIDENCE_INTERVALS": ["raw", "holdout"],
    }
    total = 0
    for method_id, fields in signatures.items():
        payload = {name: [name] for name in fields}
        value = prepare_math_arguments(method_id, payload, REG)
        assert value["status"] == "READY_ARGUMENTS_ONLY", (method_id, value)
        assert value["args"] == [payload[name] for name in fields]
        assert value["handler_invoked"] is False
        assert value["execution_authorized"] is False
        assert value["cutover_eligible"] is False
        total += 1
        assert prepare_math_arguments(method_id, {}, REG)["reason"] == "REQUIRED_ARGUMENT_MISSING"
        total += 1
        assert prepare_math_arguments(method_id, {**payload, "unknown": True}, REG)["reason"] == "UNEXPECTED_ARGUMENT"
        total += 1
    assert prepare_math_arguments("UNKNOWN", {}, REG)["reason"] == "METHOD_ID_NOT_UNIQUE"
    total += 1
    cloned = deepcopy(REG)
    target = next(x for x in cloned["methods"] if x["method_id"] == "DELTA_DEBUGGING")
    target["candidate_implementation"]["invocation_authorized"] = True
    assert prepare_math_arguments("DELTA_DEBUGGING", {"atoms": ["a"]}, cloned)["status"] == "BLOCK"
    total += 1
    assert prepare_math_arguments("DELTA_DEBUGGING", {"atoms": ["a"]}, REG)["externally_bound"] == ["reproduces_failure"]
    total += 1
    print("PASS_PROFILE_MATH_PAYLOAD_BINDING checks=%d source_only=5 no_method_invocation=1" % total)
    return total


if __name__ == "__main__":
    run()
