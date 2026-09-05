#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run_checked(argv: list[str], label: str) -> str:
    proc = subprocess.run(argv, text=True, capture_output=True)
    if proc.stdout:
        print(proc.stdout, end="" if proc.stdout.endswith("\n") else "\n")
    if proc.stderr:
        print(proc.stderr, file=sys.stderr, end="" if proc.stderr.endswith("\n") else "\n")
    if proc.returncode != 0:
        raise SystemExit(f"FAIL_{label}: exit={proc.returncode}")
    return proc.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()
    repo_root = Path(args.repo_root).resolve()
    here = repo_root / "sandbox/lf_contract_gate_test"

    core = here / "PR93_LOTE_E16_RATIFICATION_CORE_V1.py"
    trajectory = here / "GOV018_STRUCTURAL_IDENTIFIER_TRAJECTORY_V1.py"
    c7_shadow = here / "s28_ready_for_review_dedupe_shadow.py"

    run_checked(
        [sys.executable, str(core), "--repo-root", str(repo_root)],
        "E16_RATIFICATION_CORE",
    )
    output = run_checked(
        [sys.executable, str(trajectory), str(repo_root)],
        "GOV018_TRAJECTORY_EVAL",
    )

    lines = [line for line in output.splitlines() if line.strip()]
    if not lines:
        raise SystemExit("FAIL_GOV018_RESULT_MISSING")
    try:
        result = json.loads(lines[-1])
    except json.JSONDecodeError as exc:
        raise SystemExit("FAIL_GOV018_RESULT_NOT_JSON") from exc

    required = {
        "schema_version": "gov018-trajectory-eval/v1",
        "policy_code": "GOV-018",
        "result": "PASS",
        "cases_passed": 6,
        "cases_total": 6,
        "mutation_tests_passed": 3,
        "mutation_tests_total": 3,
        "correct_result_wrong_path_blocked": True,
        "live_policy_bound": True,
        "production_authorized": False,
    }
    mismatches = {
        key: {"expected": expected, "observed": result.get(key)}
        for key, expected in required.items()
        if result.get(key) != expected
    }
    if mismatches:
        raise SystemExit("FAIL_GOV018_TRAJECTORY_RESULT: " + json.dumps(mismatches, sort_keys=True))

    print("PASS_GOV018_STRUCTURAL_IDENTIFIER_TRAJECTORY=9/9")

    c7_output = run_checked(
        [sys.executable, str(c7_shadow)],
        "S28_C7_READY_DEDUPE_SHADOW",
    )
    c7_lines = [line for line in c7_output.splitlines() if line.strip()]
    if not c7_lines:
        raise SystemExit("FAIL_S28_C7_READY_DEDUPE_RESULT_MISSING")
    try:
        c7_result = json.loads(c7_lines[-1])
    except json.JSONDecodeError as exc:
        raise SystemExit("FAIL_S28_C7_READY_DEDUPE_RESULT_NOT_JSON") from exc

    c7_required = {
        "result": "PASS",
        "cases": 14,
        "passed": 14,
        "false_skip_tolerance": 0,
        "positive_control": "PR257",
        "negative_base_drift_control": "PR540",
        "production_authorized": False,
    }
    c7_mismatches = {
        key: {"expected": expected, "observed": c7_result.get(key)}
        for key, expected in c7_required.items()
        if c7_result.get(key) != expected
    }
    if c7_mismatches:
        raise SystemExit("FAIL_S28_C7_READY_DEDUPE_RESULT: " + json.dumps(c7_mismatches, sort_keys=True))

    print("PASS_S28_C7_READY_DEDUPE_SHADOW=14/14")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
