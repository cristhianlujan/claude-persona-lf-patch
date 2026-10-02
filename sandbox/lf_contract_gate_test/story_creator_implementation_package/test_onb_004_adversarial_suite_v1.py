#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from story_implementation_authority_checks_v1 import (
    materialize_authority_positive,
    set_pointer,
    validate_authority,
)
from validate_story_implementation_package_v1 import valid_fixture, validate_package

HERE = Path(__file__).resolve().parent
SUITE = HERE / "fixtures" / "onb_004_adversarial_cases_v1.json"
AUTHORITY = HERE / "fixtures" / "onb_004_authority_snapshot_20261002.json"


def mutate(pkg: dict, snapshot: dict, mutation: dict) -> None:
    kind = mutation["kind"]
    if kind == "package_pointer":
        set_pointer(pkg, mutation["pointer"], mutation["value"])
        return
    if kind == "assertion_field":
        for assertion in snapshot["authority_assertions"]:
            if assertion.get("package_pointer") == mutation["pointer"]:
                assertion[mutation["field"]] = mutation["value"]
                return
        raise AssertionError(f"assertion not found: {mutation['pointer']}")
    if kind == "remove_assertion":
        before = len(snapshot["authority_assertions"])
        snapshot["authority_assertions"] = [
            a for a in snapshot["authority_assertions"]
            if a.get("package_pointer") != mutation["pointer"]
        ]
        if len(snapshot["authority_assertions"]) == before:
            raise AssertionError(f"assertion not found: {mutation['pointer']}")
        return
    if kind == "append_reuse_decision":
        pkg["architecture_and_reuse_decisions"].append(copy.deepcopy(mutation["value"]))
        return
    if kind == "capability_state":
        snapshot[mutation["key"]]["state"] = mutation["value"]
        return
    raise AssertionError(f"unsupported mutation kind: {kind}")


def main() -> int:
    suite = json.loads(SUITE.read_text(encoding="utf-8"))
    authority = json.loads(AUTHORITY.read_text(encoding="utf-8"))
    if suite.get("schema_version") != "ONB_004_ADVERSARIAL_SUITE_V1":
        raise SystemExit("ADVERSARIAL_SUITE_SCHEMA_INVALID")

    positive = materialize_authority_positive(valid_fixture(), authority)
    baseline_errors = validate_package(positive) + validate_authority(positive, authority)
    if baseline_errors:
        print(json.dumps({"result":"FAIL","baseline_errors":baseline_errors}, indent=2, sort_keys=True))
        return 1

    results = []
    for case in suite["cases"]:
        pkg = copy.deepcopy(positive)
        snapshot = copy.deepcopy(authority)
        mutate(pkg, snapshot, case["mutation"])
        errors = validate_package(pkg)
        if not errors:
            errors.extend(validate_authority(pkg, snapshot))
        expected = case["expected_error"]
        ok = expected in errors
        results.append({"case":case["case"],"expected":expected,"ok":ok,"errors":errors})

    passed = sum(1 for item in results if item["ok"])
    out = {
        "schema":"SC_M3_2_ONB_004_ADVERSARIAL_RESULT_V1",
        "cases_total":len(results),
        "cases_passed":passed,
        "result":"PASS" if passed == len(results) else "FAIL",
        "results":results,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
