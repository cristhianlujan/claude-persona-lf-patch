#!/usr/bin/env python3
"""M8.11 / REGRESSION_GATE_NEGATIVE: exercise the existing M8.10 gate, without inventing a relative regression threshold.

This intentionally returns nonzero if the current gate misses a p95 deterioration
which remains below the canonical 150s SLO. A missing policy is NOT a PASS.
Read-only, no production modification, no sample/receipt fabrication.
"""
import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path

TEST_CODE = "ENG_M8_11_REGRESSION_GATE_NEGATIVE"


def load_gate(path: Path):
    spec = importlib.util.spec_from_file_location("ig_m8_10_slo", str(path))
    if not spec or not spec.loader:
        raise RuntimeError("CANONICAL_M8_10_GATE_NOT_LOADABLE")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if getattr(mod, "TEST_CODE", None) != "ENG_M8_10_SLO_OVER_LIMIT_NEGATIVE":
        raise RuntimeError("CANONICAL_M8_10_GATE_IDENTITY_MISMATCH")
    return mod.judge


def run(snapshot: dict, judge) -> dict:
    bound = (
        snapshot.get("schema") == "IG_M8_10_SLO_SNAPSHOT_V1"
        and snapshot.get("limit_source") == "M8.0/INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1"
    )
    if not bound:
        raise RuntimeError("M8_10_BASELINE_SEMANTIC_AUTHORITY_MISSING")
    limit = snapshot["edge_limit_ms"]
    minimum = snapshot["min_samples"]
    baseline = snapshot["compute_per_invocation"]
    p95 = baseline["p95_ms"]
    if not (isinstance(p95, (int, float)) and 0 < p95 < limit):
        raise RuntimeError("M8_10_BASELINE_NOT_ADMISSIBLE")

    baseline_problems = judge(baseline, limit, minimum)
    # Mutation A: severe slowdown beyond the actual, contract-bound SLO.
    severe = copy.deepcopy(baseline)
    severe["p95_ms"] = limit + 1
    severe["p99_ms"] = limit + 2
    severe_problems = judge(severe, limit, minimum)

    # Mutation B: adversarial performance regression that remains below the SLO.
    # +25% is a PROBE, not a newly authorized regression tolerance.
    moderate = copy.deepcopy(baseline)
    moderate["p95_ms"] = min(limit - 1, round(p95 * 1.25))
    moderate["p99_ms"] = max(moderate["p99_ms"], moderate["p95_ms"])
    moderate_problems = judge(moderate, limit, minimum)
    if moderate["p95_ms"] <= p95:
        raise RuntimeError("ADVERSARIAL_INJECTION_DID_NOT_DEGRADE_BASELINE")

    relative_gap = not moderate_problems
    ok = not baseline_problems and bool(severe_problems) and not relative_gap
    return {
        "test_code": TEST_CODE,
        "status": "PASS" if ok else "FAIL",
        "baseline_p95_ms": p95,
        "slo_limit_ms": limit,
        "adversarial_cases": [
            {"case": "P95_ABOVE_SLO", "mutated_p95_ms": severe["p95_ms"],
             "gate_rejected": bool(severe_problems), "reason": severe_problems},
            {"case": "P95_RELATIVE_DEGRADATION_BELOW_SLO", "mutated_p95_ms": moderate["p95_ms"],
             "gate_rejected": bool(moderate_problems), "reason": moderate_problems,
             "probe_not_governance_tolerance": True}
        ],
        "critical_gap": "RELATIVE_P95_REGRESSION_UNDETECTED_BY_EXISTING_GATE" if relative_gap else None,
        "policy_gap": "M8_11_RELATIVE_REGRESSION_TOLERANCE_NOT_DECLARED_IN_M8_10_BASELINE",
        "observed": {
            "test_passed": ok,
            "test_exit_code": 0 if ok else 1,
            "semantic_authority_bound": bound,
            "adversarial_case_executed": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--gate", required=True)
    args = parser.parse_args()
    try:
        snapshot = json.loads(Path(args.snapshot).read_text())
        out = run(snapshot, load_gate(Path(args.gate)))
    except Exception as e:
        out = {"test_code": TEST_CODE, "status": "ERROR", "error": str(e),
               "observed": {"test_passed": False, "test_exit_code": 2,
                            "semantic_authority_bound": False, "adversarial_case_executed": False}}
    print(json.dumps(out, indent=2, sort_keys=True))
    return out["observed"]["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
