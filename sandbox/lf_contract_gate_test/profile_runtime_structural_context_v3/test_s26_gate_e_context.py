#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from s26_hp001.gate_d_authority import evaluate_authority_resolution
from s26_hp001.gate_e_context import GateETypedContextBlocked, _validate_payload, evaluate_typed_context

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "s26_hp001"
OUTPUT = FIXTURE / "gate_e_output.json"


def load_payload() -> dict:
    value = json.loads(OUTPUT.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("GATE_E_FIXTURE_NOT_OBJECT")
    return value


def expect_block(name: str, payload: dict, gate_d: dict, contains: str) -> str:
    try:
        _validate_payload(payload, gate_d)
    except GateETypedContextBlocked as exc:
        text = str(exc)
        if contains not in text:
            raise RuntimeError(f"GATE_E_NEGATIVE_WRONG_BLOCK:{name}:{text}")
        return text
    raise RuntimeError(f"GATE_E_NEGATIVE_FALSE_PASS:{name}")


def main() -> int:
    gate_d = evaluate_authority_resolution()
    positive = evaluate_typed_context(gate_d)
    if positive["output"]["status"] != "PASS":
        raise RuntimeError("GATE_E_POSITIVE_NOT_PASS")
    if positive["adapter_binding_count"] != 0:
        raise RuntimeError("GATE_E_POSITIVE_ADAPTER_COUNT_INVALID")
    if positive["authority_count"] != 4:
        raise RuntimeError("GATE_E_POSITIVE_AUTHORITY_COUNT_INVALID")

    base = load_payload()
    negatives = {}

    x = copy.deepcopy(base)
    x["upstream"]["source_output_sha256"] = "0" * 64
    negatives["wrong_d_sha"] = expect_block("wrong_d_sha", x, gate_d, "GATE_E_UPSTREAM_OUTPUT_SHA_MISMATCH")

    x = copy.deepcopy(base)
    x["run_id"] = "S26-HP-WRONG"
    negatives["run_mismatch"] = expect_block("run_mismatch", x, gate_d, "GATE_E_IDENTITY_INVALID")

    x = copy.deepcopy(base)
    x["typed_context"]["schema"] = "LF_RUNTIME_TYPED_CONTEXT_WRONG"
    negatives["typed_schema"] = expect_block("typed_schema", x, gate_d, "GATE_E_TYPED_CONTEXT_NOT_RESOLVER_EXACT")

    x = copy.deepcopy(base)
    x["resolver_input"]["runtime_context"]["input_fields"]["profile_slug"] = "wrong_profile"
    negatives["profile_slug"] = expect_block("profile_slug", x, gate_d, "GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["resolver_input"]["runtime_context"]["input_fields"]["output_contract_version"] = "WRONG"
    negatives["output_contract"] = expect_block("output_contract", x, gate_d, "GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["resolver_input"]["runtime_context"]["required_adapter_codes"] = ["ADAPTER_REQUIRED_TEST"]
    negatives["required_adapter_missing"] = expect_block("required_adapter_missing", x, gate_d, "GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["policy"]["paid_fallback_allowed"] = True
    negatives["paid_fallback"] = expect_block("paid_fallback", x, gate_d, "GATE_E_POLICY_BOUNDARY_INVALID")

    x = copy.deepcopy(base)
    x["next_gate"] = "WRONG"
    negatives["wrong_next_gate"] = expect_block("wrong_next_gate", x, gate_d, "GATE_E_TRANSITION_INVALID")

    print(json.dumps({
        "gate": "S26_HP001_GATE_E_TYPED_CONTEXT_MATRIX_V1",
        "result": "PASS",
        "positive": {
            "output_sha256": positive["output_sha256"],
            "typed_context_sha256": positive["typed_context_sha256"],
            "adapter_binding_count": positive["adapter_binding_count"],
            "authority_count": positive["authority_count"],
            "next_gate": positive["output"]["next_gate"],
        },
        "negative_controls": negatives,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
