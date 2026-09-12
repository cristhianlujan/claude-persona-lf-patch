#!/usr/bin/env python3
from __future__ import annotations

import copy
import json

from s26_hp001.gate_f import GateFBlocked, evaluate_gate_f, validate_gate_f_payload


def expect_block(name, payload, code, f_sha, obs_sha):
    try:
        validate_gate_f_payload(payload, f_input_sha=f_sha, observation_sha=obs_sha)
    except GateFBlocked as exc:
        if str(exc) != code:
            raise RuntimeError(f"{name}:EXPECTED={code}:ACTUAL={exc}") from exc
        return code
    raise RuntimeError(f"{name}:FALSE_PASS")


def main() -> int:
    current = evaluate_gate_f()
    if current["status"] not in {"BLOCKED", "PASS"}:
        raise RuntimeError("GATE_F_CURRENT_STATUS_INVALID")
    if current["status"] == "BLOCKED" and current["next_gate_authorized"] is not False:
        raise RuntimeError("GATE_F_BLOCKED_AUTHORIZATION_INVALID")
    if current["status"] == "PASS" and current["next_gate_authorized"] is not True:
        raise RuntimeError("GATE_F_PASS_AUTHORIZATION_INVALID")

    payload = current["output"]
    f_sha = current["gate_f_input_sha256"]
    obs_sha = current["runtime_observation_sha256"]
    negatives = {}

    x = copy.deepcopy(payload)
    x["status"] = "PASS"
    x["next_gate"] = "G_STRUCTURED_OUTPUT"
    x["decision"]["exact_head_runtime_observed"] = False
    negatives["exact_runtime_false_pass"] = expect_block(
        "exact_runtime_false_pass", x,
        "GATE_F_FALSE_PASS_WITHOUT_EXACT_RUNTIME_EVIDENCE", f_sha, obs_sha
    )

    x = copy.deepcopy(payload)
    x["historical_manual_candidate"]["consumed_current_gate_f_boundary"] = True
    negatives["manual_receipt_false_credit"] = expect_block(
        "manual_receipt_false_credit", x,
        "GATE_F_HISTORICAL_MANUAL_FALSE_CREDIT", f_sha, obs_sha
    )

    x = copy.deepcopy(payload)
    x["runtime_observation"]["gate_authority"] = True
    negatives["runtime_observation_promoted"] = expect_block(
        "runtime_observation_promoted", x,
        "GATE_F_OBSERVATION_WRONGLY_AUTHORIZED", f_sha, obs_sha
    )

    x = copy.deepcopy(payload)
    if payload["status"] == "PASS":
        x["next_gate"] = None
        negatives["downstream_state_invalid"] = expect_block(
            "downstream_state_invalid", x,
            "GATE_F_PASS_NEXT_GATE_INVALID", f_sha, obs_sha
        )
    else:
        x["next_gate"] = "G_STRUCTURED_OUTPUT"
        negatives["downstream_state_invalid"] = expect_block(
            "downstream_state_invalid", x,
            "GATE_F_BLOCKED_BUT_DOWNSTREAM_AUTHORIZED", f_sha, obs_sha
        )

    x = copy.deepcopy(payload)
    x["execution_requirement"]["model_generation_performance_required"] = False
    negatives["performance_requirement_removed"] = expect_block(
        "performance_requirement_removed", x,
        "GATE_F_PERFORMANCE_REQUIREMENT_MISSING", f_sha, obs_sha
    )

    x = copy.deepcopy(payload)
    x["execution_requirement"]["max_acceptable_model_generation_ms"] = 240000.0
    negatives["performance_budget_weakened"] = expect_block(
        "performance_budget_weakened", x,
        "GATE_F_PERFORMANCE_BUDGET_INVALID:max_acceptable_model_generation_ms", f_sha, obs_sha
    )

    print(json.dumps({
        "gate": "S26_HP001_GATE_F_RUNTIME_MATRIX_V2",
        "result": "PASS",
        "current_status": current["status"],
        "next_gate_authorized": current["next_gate_authorized"],
        "gate_f_output_sha256": current["output_sha256"],
        "gate_f_input_sha256": f_sha,
        "runtime_observation_sha256": obs_sha,
        "negative_case_count": len(negatives),
        "negative_cases": negatives,
        "production_effect": False,
        "claim_ceiling": (
            "GATE_F_PASS_EXACT_HEAD_RUNTIME_VERIFIED_NOT_GOLDEN"
            if current["status"] == "PASS"
            else "GATE_F_BLOCKED_EXACT_HEAD_RUNTIME_NOT_EXECUTED_NOT_GOLDEN"
        ),
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
