#!/usr/bin/env python3
"""ENG_M5_6_PARITY_PER_STRATEGY

Bounded verifier for IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.6 /
PARITY_PER_STRATEGY.

The executable strategy probe is produced against the canonical database inside
isolated PostgreSQL subtransactions and MUST prove rollback/no persistent delta.
This verifier never synthesizes strategy outputs and never connects to a
different database.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

TEST_CODE = "ENG_M5_6_PARITY_PER_STRATEGY"
SEMANTIC_AUTHORITY = "CANONICAL_PLAN_EXIT_CRITERION:paridad con golden 5.13 por estrategia"

EXPECTED = {
    "BOOTSTRAP": {
        "mode": "GOVERNED_CANONICAL_BOOTSTRAP_V1",
        "status": "VALIDATOR_RUNTIME_REQUIRED",
        "family_count": 47,
    },
    "REBIND": {
        "mode": "RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1",
        "status": "VALIDATOR_RUNTIME_REQUIRED",
        "family_count": 47,
    },
    "SOURCE_STALE": {
        "mode": "RUNTIME_GOVERNED_RECURATION_V2",
        "status": "VALIDATOR_RUNTIME_REQUIRED",
        "family_count": 47,
        "source_stale_proof": "INPUT_FRESHNESS_DELTA_V1",
    },
    "FULL": {
        "mode": "RUNTIME_GOVERNED_RECURATION_V2",
        "status": "VALIDATOR_RUNTIME_REQUIRED",
        "family_count": 47,
    },
}


def die(code: str, details: Any = None) -> int:
    payload = {
        "status": "FAIL",
        "test_code": TEST_CODE,
        "code": code,
        "observed": {
            "test_passed": False,
            "test_exit_code": 1,
            "semantic_authority_bound": True,
            "adversarial_case_executed": bool(
                isinstance(details, dict) and details.get("adversarial_case_executed")
            ),
        },
        "details": details,
    }
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe-json", required=True)
    args = ap.parse_args()

    try:
        probe = json.loads(args.probe_json)
    except Exception as exc:
        return die("PROBE_JSON_INVALID", {"error": str(exc)})

    if not isinstance(probe, dict):
        return die("PROBE_OBJECT_REQUIRED")

    if probe.get("schema_version") != "M56_PARITY_PROBE_V1":
        return die("PROBE_SCHEMA_MISMATCH", probe.get("schema_version"))

    if probe.get("semantic_authority") != SEMANTIC_AUTHORITY:
        return die("SEMANTIC_AUTHORITY_MISMATCH", probe.get("semantic_authority"))

    if probe.get("transaction_method") != "PLPGSQL_SUBTRANSACTION_ROLLBACK":
        return die("TRANSACTION_METHOD_MISMATCH", probe.get("transaction_method"))

    if probe.get("rollback_verified") is not True:
        return die("ROLLBACK_NOT_VERIFIED")

    delta = probe.get("persistent_delta")
    if not isinstance(delta, dict) or delta.get("runs") != 0 or delta.get("assessments") != 0:
        return die("PERSISTENT_DELTA_NONZERO", delta)

    golden_modes = set(probe.get("golden_modes_seen") or [])
    required_modes = {
        "GOVERNED_CANONICAL_BOOTSTRAP_V1",
        "RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1",
        "RUNTIME_GOVERNED_RECURATION_V2",
    }
    if not required_modes.issubset(golden_modes):
        return die(
            "GOLDEN_5_13_MODE_COVERAGE_MISSING",
            {"required": sorted(required_modes), "seen": sorted(golden_modes)},
        )

    strategies = probe.get("strategies")
    if not isinstance(strategies, dict):
        return die("STRATEGIES_OBJECT_REQUIRED")

    verified: dict[str, Any] = {}
    for strategy, expected in EXPECTED.items():
        item = strategies.get(strategy)
        if not isinstance(item, dict):
            return die("STRATEGY_RESULT_MISSING", {"strategy": strategy})
        if item.get("executed") is not True:
            return die("STRATEGY_NOT_EXECUTED", {"strategy": strategy, "item": item})
        if item.get("rollback_verified") is not True:
            return die("STRATEGY_ROLLBACK_NOT_VERIFIED", {"strategy": strategy})
        if item.get("result_class") != "MATERIALIZED":
            return die("STRATEGY_NOT_MATERIALIZED", {"strategy": strategy, "item": item})
        for field, value in expected.items():
            if item.get(field) != value:
                return die(
                    "STRATEGY_PARITY_MISMATCH",
                    {
                        "strategy": strategy,
                        "field": field,
                        "expected": value,
                        "actual": item.get(field),
                    },
                )
        if item.get("promotion_authorized") is not False:
            return die("PROMOTION_AUTHORITY_DRIFT", {"strategy": strategy})
        if item.get("production_authorized") is not False:
            return die("PRODUCTION_AUTHORITY_DRIFT", {"strategy": strategy})
        verified[strategy] = {
            "mode": item.get("mode"),
            "status": item.get("status"),
            "family_count": item.get("family_count"),
        }

    adversarial = probe.get("adversarial")
    if not isinstance(adversarial, dict):
        return die("ADVERSARIAL_RESULT_MISSING")
    if adversarial.get("executed") is not True or adversarial.get("blocked") is not True:
        return die(
            "ADVERSARIAL_CASE_NOT_BLOCKED",
            {"adversarial_case_executed": bool(adversarial.get("executed")), "item": adversarial},
        )
    if adversarial.get("error_code") != "INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID":
        return die(
            "ADVERSARIAL_ERROR_MISMATCH",
            {
                "adversarial_case_executed": True,
                "expected": "INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID",
                "actual": adversarial.get("error_code"),
            },
        )
    if adversarial.get("rollback_verified") is not True:
        return die("ADVERSARIAL_ROLLBACK_NOT_VERIFIED", {"adversarial_case_executed": True})

    result = {
        "status": "PASS",
        "test_code": TEST_CODE,
        "observed": {
            "test_passed": True,
            "test_exit_code": 0,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "rollback_verified": True,
            "strategy_count": 4,
            "persistent_delta": {"runs": 0, "assessments": 0},
        },
        "semantic_authority": SEMANTIC_AUTHORITY,
        "verified_strategies": verified,
        "adversarial_error_code": adversarial.get("error_code"),
        "probe_receipt_sha256": probe.get("probe_receipt_sha256"),
    }
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
