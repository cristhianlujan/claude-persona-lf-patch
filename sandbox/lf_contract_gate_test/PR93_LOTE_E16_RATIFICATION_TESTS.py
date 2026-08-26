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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
