#!/usr/bin/env python3
from __future__ import annotations

import copy
import json

from s26_hp001.bootstrap_context import BootstrapBlocked, evaluate_bootstrap, load_bootstrap, validate_bootstrap


def expect_block(name: str, payload: dict, contains: str) -> str:
    try:
        validate_bootstrap(payload)
    except BootstrapBlocked as exc:
        text = str(exc)
        if contains not in text:
            raise RuntimeError(f"BOOTSTRAP_NEGATIVE_WRONG_BLOCK:{name}:{text}")
        return text
    raise RuntimeError(f"BOOTSTRAP_NEGATIVE_FALSE_PASS:{name}")


def main() -> int:
    base = load_bootstrap()
    positive = evaluate_bootstrap()
    if positive["execution_mode"] != "SANDBOX":
        raise RuntimeError("BOOTSTRAP_POSITIVE_MODE_INVALID")
    if positive["distribution_mode"] != "DIRECT":
        raise RuntimeError("BOOTSTRAP_POSITIVE_DISTRIBUTION_INVALID")
    if positive["active_policy_count"] != 4:
        raise RuntimeError("BOOTSTRAP_POSITIVE_POLICY_COUNT_INVALID")

    negatives = {}

    x = copy.deepcopy(base)
    x.pop("execution_mode", None)
    negatives["missing_execution_mode"] = expect_block("missing_execution_mode", x, "BOOTSTRAP_EXECUTION_MODE_INVALID")

    x = copy.deepcopy(base)
    x["execution_mode"] = "PROD_CONTROLLED"
    negatives["production_mode"] = expect_block("production_mode", x, "BOOTSTRAP_EXECUTION_MODE_INVALID")

    x = copy.deepcopy(base)
    x["policy_resolution"]["active_policy_refs"] = x["policy_resolution"]["active_policy_refs"][:-1]
    x["policy_resolution"]["resolved_policy_count"] = 3
    negatives["missing_required_policy"] = expect_block("missing_required_policy", x, "BOOTSTRAP_REQUIRED_POLICY_SET_MISMATCH")

    x = copy.deepcopy(base)
    x["policy_resolution"]["active_policy_refs"][0]["policy_sha"] = "0" * 64
    negatives["wrong_policy_sha"] = expect_block("wrong_policy_sha", x, "BOOTSTRAP_POLICY_SHA_MISMATCH")

    x = copy.deepcopy(base)
    x["policy_resolution"]["active_policy_snapshot_sha256"] = "0" * 64
    negatives["snapshot_drift"] = expect_block("snapshot_drift", x, "BOOTSTRAP_POLICY_SNAPSHOT_SHA_MISMATCH")

    x = copy.deepcopy(base)
    x["development_assurance"]["status"] = "ACTIVE"
    negatives["candidate_misrepresented_active"] = expect_block("candidate_misrepresented_active", x, "BOOTSTRAP_ASSURANCE_INVALID:status")

    x = copy.deepcopy(base)
    x["development_assurance"]["direct_development_exception"]["allowed_modes"] = ["DEVELOPMENT", "TEST", "LOCAL_FIXTURE"]
    negatives["sandbox_not_allowed"] = expect_block("sandbox_not_allowed", x, "BOOTSTRAP_EXECUTION_MODE_NOT_IN_ASSURANCE")

    x = copy.deepcopy(base)
    x["router_execution_mode_resolved"] = True
    negatives["false_router_mode_provenance"] = expect_block("false_router_mode_provenance", x, "BOOTSTRAP_ROUTER_EXECUTION_MODE_FALSE_PROVENANCE")

    print(json.dumps({
        "gate": "S26_HP001_BOOTSTRAP_GOVERNANCE_MATRIX_V1",
        "result": "PASS",
        "positive": {
            "operation_code": positive["operation_code"],
            "execution_mode": positive["execution_mode"],
            "distribution_mode": positive["distribution_mode"],
            "active_policy_count": positive["active_policy_count"],
            "policy_snapshot_sha256": positive["policy_snapshot_sha256"],
            "bootstrap_context_sha256": positive["output_sha256"],
        },
        "negative_controls": negatives,
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
