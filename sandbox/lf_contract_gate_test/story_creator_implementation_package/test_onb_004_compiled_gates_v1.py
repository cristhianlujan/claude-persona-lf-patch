#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from test_onb_004_adversarial_suite_v1 import mutate
from story_implementation_authority_checks_v1 import validate_authority
from validate_story_implementation_package_v1 import validate_package

HERE = Path(__file__).resolve().parent
PACKAGE = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"
AUTHORITY = HERE / "fixtures" / "onb_004_authority_snapshot_20261002.json"
ADVERSARIAL = HERE / "fixtures" / "onb_004_adversarial_cases_v1.json"


def main() -> int:
    pkg = json.loads(PACKAGE.read_text(encoding="utf-8"))
    authority = json.loads(AUTHORITY.read_text(encoding="utf-8"))
    suite = json.loads(ADVERSARIAL.read_text(encoding="utf-8"))

    baseline_structural = validate_package(pkg)
    baseline_authority = validate_authority(pkg, authority)
    baseline_ok = not baseline_structural and not baseline_authority

    results = []
    false_passes = 0
    for case in suite["cases"]:
        candidate = copy.deepcopy(pkg)
        snapshot = copy.deepcopy(authority)
        mutate(candidate, snapshot, case["mutation"])
        errors = validate_package(candidate)
        errors.extend(validate_authority(candidate, snapshot))
        expected = case["expected_error"]
        rejected = expected in errors
        false_pass = not errors
        if false_pass:
            false_passes += 1
        results.append({
            "case": case["case"],
            "expected_error": expected,
            "rejected_as_expected": rejected,
            "false_pass": false_pass,
            "errors": errors,
        })

    adversarial_ok = all(item["rejected_as_expected"] for item in results)
    out = {
        "schema":"SC_M4_2_ONB_004_COMPILED_GATES_V1",
        "baseline_structural_pass": not baseline_structural,
        "baseline_authority_pass": not baseline_authority,
        "adversarial_cases_total": len(results),
        "adversarial_cases_rejected": sum(1 for item in results if item["rejected_as_expected"]),
        "false_pass_count": false_passes,
        "result":"PASS" if baseline_ok and adversarial_ok and false_passes == 0 else "FAIL",
        "baseline_errors": baseline_structural + baseline_authority,
        "results": results,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
