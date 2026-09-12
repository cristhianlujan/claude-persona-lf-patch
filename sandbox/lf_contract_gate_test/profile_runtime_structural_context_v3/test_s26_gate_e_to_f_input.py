#!/usr/bin/env python3
from __future__ import annotations

import copy
import json

from s26_hp001.gate_f_input import (
    GateFInputBlocked,
    _load,
    _validate_payload,
    evaluate_f_input,
    E_OUTPUT,
    F_INPUT,
    F_RECEIPT,
)


def expect_block(name: str, payload: dict, gate_e: dict, receipt: dict, contains: str) -> str:
    try:
        _validate_payload(payload, gate_e, receipt)
    except GateFInputBlocked as exc:
        text = str(exc)
        if contains not in text:
            raise RuntimeError(f"GATE_E_TO_F_NEGATIVE_WRONG_BLOCK:{name}:{text}")
        return text
    raise RuntimeError(f"GATE_E_TO_F_NEGATIVE_FALSE_PASS:{name}")


def main() -> int:
    result = evaluate_f_input()
    if result["source_e_sha256"] != "f14bd37467db623e8678d7680d8e19deb0ce7de28d673e743f7b6e33457c3e53":
        raise RuntimeError("GATE_E_TO_F_SOURCE_SHA_UNEXPECTED")
    if result["historical_f_consumption_proven"] is not False:
        raise RuntimeError("GATE_E_TO_F_FALSE_CONSUMPTION_PROOF")

    gate_e = _load(E_OUTPUT)
    base = _load(F_INPUT)
    receipt = _load(F_RECEIPT)
    negatives = {}

    x = copy.deepcopy(base)
    x["upstream"]["source_output_sha256"] = "0" * 64
    negatives["wrong_e_sha"] = expect_block("wrong_e_sha", x, gate_e, receipt, "GATE_F_INPUT_E_SHA_MISMATCH")

    x = copy.deepcopy(base)
    x["profile_input"]["typed_context_sha256"] = "0" * 64
    negatives["typed_context_drift"] = expect_block("typed_context_drift", x, gate_e, receipt, "GATE_F_INPUT_PROFILE_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["bootstrap_context"]["policy_snapshot_sha256"] = "0" * 64
    negatives["policy_snapshot_drift"] = expect_block("policy_snapshot_drift", x, gate_e, receipt, "GATE_F_INPUT_BOOTSTRAP_DRIFT:policy_snapshot_sha256")

    x = copy.deepcopy(base)
    x["profile_input"]["profile_slug"] = "wrong_profile"
    negatives["profile_drift"] = expect_block("profile_drift", x, gate_e, receipt, "GATE_F_INPUT_PROFILE_CONTEXT_DIVERGENCE")

    x = copy.deepcopy(base)
    x["current_f_compatibility"]["historical_execution_consumed_this_boundary"] = True
    negatives["retroactive_consumption_claim"] = expect_block("retroactive_consumption_claim", x, gate_e, receipt, "GATE_F_INPUT_FALSE_HISTORICAL_CONSUMPTION_CLAIM")

    x = copy.deepcopy(base)
    x["acceptance_requirements"]["quality_depth_performance_contract_sha256"] = "0" * 64
    negatives["qdp_contract_sha_drift"] = expect_block("qdp_contract_sha_drift", x, gate_e, receipt, "GATE_F_INPUT_QDP_SHA_MISMATCH")

    x = copy.deepcopy(base)
    x["acceptance_requirements"]["quality_required"] = False
    negatives["quality_gate_disabled"] = expect_block("quality_gate_disabled", x, gate_e, receipt, "GATE_F_INPUT_QDP_REQUIREMENTS_DIVERGENCE")

    x = copy.deepcopy(base)
    x["acceptance_requirements"]["model_generation_latency_required_at_gate_f"] = False
    negatives["runtime_perf_gate_disabled"] = expect_block("runtime_perf_gate_disabled", x, gate_e, receipt, "GATE_F_INPUT_QDP_REQUIREMENTS_DIVERGENCE")

    print(json.dumps({
        "gate": "S26_HP001_GATE_E_TO_F_INPUT_MATRIX_V2",
        "result": "PASS",
        "source_gate": "E_ADAPTER_TYPED_CONTEXT",
        "source_e_sha256": result["source_e_sha256"],
        "gate_f_input_sha256": result["output_sha256"],
        "typed_context_sha256": result["typed_context_sha256"],
        "bootstrap_context_sha256": result["bootstrap_context_sha256"],
        "policy_snapshot_sha256": result["policy_snapshot_sha256"],
        "quality_depth_performance_contract_sha256": result["quality_depth_performance_contract_sha256"],
        "f_compatibility_proven": result["f_compatibility_proven"],
        "historical_f_consumption_proven": result["historical_f_consumption_proven"],
        "negative_controls": negatives,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
