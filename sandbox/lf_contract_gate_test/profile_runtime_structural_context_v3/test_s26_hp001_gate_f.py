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
    if current["status"] != "BLOCKED" or current["next_gate_authorized"] is not False:
        raise RuntimeError("GATE_F_CURRENT_BLOCK_EXPECTED")
    payload = current["output"]
    f_sha = current["gate_f_input_sha256"]
    obs_sha = current["runtime_observation_sha256"]
    negatives = {}

    x = copy.deepcopy(payload); x["status"] = "PASS"; x["next_gate"] = "G_STRUCTURED_OUTPUT"
    negatives["source_mismatch_false_pass"] = expect_block(
        "source_mismatch_false_pass", x, "GATE_F_FALSE_PASS_WITHOUT_EXACT_RUNTIME_EVIDENCE", f_sha, obs_sha
    )

    x = copy.deepcopy(payload); x["historical_manual_candidate"]["consumed_current_gate_f_boundary"] = True
    negatives["manual_receipt_false_credit"] = expect_block(
        "manual_receipt_false_credit", x, "GATE_F_HISTORICAL_MANUAL_FALSE_CREDIT", f_sha, obs_sha
    )

    x = copy.deepcopy(payload); x["runtime_observation"]["gate_authority"] = True
    negatives["stale_runtime_observation_promoted"] = expect_block(
        "stale_runtime_observation_promoted", x, "GATE_F_OBSERVATION_WRONGLY_AUTHORIZED", f_sha, obs_sha
    )

    x = copy.deepcopy(payload); x["next_gate"] = "G_STRUCTURED_OUTPUT"
    negatives["blocked_downstream_authorized"] = expect_block(
        "blocked_downstream_authorized", x, "GATE_F_BLOCKED_BUT_DOWNSTREAM_AUTHORIZED", f_sha, obs_sha
    )

    x = copy.deepcopy(payload); x["execution_requirement"]["model_generation_performance_required"] = False
    negatives["performance_requirement_removed"] = expect_block(
        "performance_requirement_removed", x, "GATE_F_PERFORMANCE_REQUIREMENT_MISSING", f_sha, obs_sha
    )

    print(json.dumps({
        "gate": "S26_HP001_GATE_F_RUNTIME_MATRIX_V1",
        "result": "PASS",
        "current_status": current["status"],
        "gate_f_output_sha256": current["output_sha256"],
        "gate_f_input_sha256": f_sha,
        "runtime_observation_sha256": obs_sha,
        "negative_case_count": len(negatives),
        "negative_cases": negatives,
        "production_effect": False,
        "claim_ceiling": "GATE_F_BLOCKED_EXACT_HEAD_RUNTIME_NOT_EXECUTED_NOT_GOLDEN"
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
