#!/usr/bin/env python3
"""Read-only, Git-anchored per-case qualification for M7.11 CI-* candidates.

This is test evidence, NOT a provenance receipt, case activation, scoped PASS,
downstream authorization, or production authority.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
from change_impact_l3c_resolver_readonly_v1 import resolve_change

ANCHORS = {
    "change_impact_l3c_gold_50.sql": "cfe2731c872e334d95523a3c7f085c31f92a6f70",
    "change_impact_l3c_adjudicated_gold_v2.json": "32ec59b23a70e09b77245579145233a5ee462c11",
}
VALID_DECISIONS = {"SCOPED_CANDIDATE", "SCOPED_BLOCK", "GLOBAL_ESCALATE", "HUMAN_REQUIRED"}
EXPECTED_COUNT = 50
EXPECTED_ADVERSARIAL = 10


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def evaluate() -> dict:
    anchors = {}
    for name, expected in ANCHORS.items():
        path = HERE / name
        observed = git("hash-object", str(path))
        require(observed == expected, f"GIT_BLOB_DRIFT:{name}:{observed}")
        anchors[name] = observed

    base = (HERE / "change_impact_l3c_gold_50.sql").read_text()
    ids_base = re.findall(r"\('(CI-[A-Z]+-\d\d)'", base)
    gold_doc = json.loads((HERE / "change_impact_l3c_adjudicated_gold_v2.json").read_text())
    inputs_doc = json.loads((HERE / "change_impact_l3c_structured_inputs_v1.json").read_text())
    require(gold_doc.get("schema") == "INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2", "ORACLE_SCHEMA_CHANGED")
    require(set(gold_doc.get("authorization", {}).values()) == {False}, "ORACLE_AUTHORIZATION_NOT_CLOSED")
    require(len(ids_base) == EXPECTED_COUNT and len(set(ids_base)) == EXPECTED_COUNT, "BASE_NOT_50_UNIQUE")
    require(len(gold_doc["cases"]) == EXPECTED_COUNT and len(inputs_doc["cases"]) == EXPECTED_COUNT, "INPUT_OR_ORACLE_NOT_50")
    gold = {x["case_id"]: x for x in gold_doc["cases"]}
    ids_input = [x["case_id"] for x in inputs_doc["cases"]]
    require(len(gold) == EXPECTED_COUNT and len(set(ids_input)) == EXPECTED_COUNT, "DUPLICATE_CASE_ID")
    require(set(ids_base) == set(gold) == set(ids_input), "GIT_SOURCE_ID_MISMATCH")

    forbidden = set(inputs_doc["anti_leakage"]["forbidden_input_fields"])
    rows = []
    for source in inputs_doc["cases"]:
        case_id = source["case_id"]
        leak = forbidden & (set(source) | set(source.get("facts", {})))
        require(not leak, f"ORACLE_LEAKAGE:{case_id}:{sorted(leak)}")
        actual = resolve_change({
            "subject_kind": source["subject_kind"],
            "change_kind": source["change_kind"],
            "facts": source["facts"],
        })
        expected = gold[case_id]
        ok = (actual["decision"] == expected["decision"]
              and set(actual["impact_families"]) == set(expected["impact_families"])
              and actual["decision"] in VALID_DECISIONS)
        rows.append({
            "case_id": case_id,
            "status": "PASS" if ok else "FAIL",
            "expected_decision": expected["decision"],
            "observed_decision": actual["decision"],
            "expected_impact_families": sorted(expected["impact_families"]),
            "observed_impact_families": sorted(actual["impact_families"]),
        })

    # The pre-existing evaluator supplies adversarial, no-underblock, and anti-leakage checks.
    raw = subprocess.check_output(
        [sys.executable, str(HERE / "validate_change_impact_l3c_resolver_v1.py")],
        text=True,
    )
    benchmark = json.loads(raw)
    passed = sum(r["status"] == "PASS" for r in rows)
    require(passed == EXPECTED_COUNT, f"CASE_FAIL:{EXPECTED_COUNT - passed}")
    require(benchmark["exact_decision_passed"] == EXPECTED_COUNT, "DECISION_TEST_FAILED")
    require(benchmark["exact_impact_set_passed"] == EXPECTED_COUNT, "IMPACT_TEST_FAILED")
    require(benchmark["unsafe_under_block"] == 0, "UNSAFE_UNDERBLOCK")
    require(benchmark["unknown_mixed_shared_fail_closed"]["passed"] == EXPECTED_ADVERSARIAL, "ADVERSARIAL_NOT_PASS")
    require(not benchmark["anti_leakage"]["forbidden_fields_found"], "ORACLE_LEAKAGE")
    require(all(v is False for v in benchmark["authorization"].values()), "AUTHORIZATION_MUST_REMAIN_FALSE")

    return {
        "schema_version": "IG_CI50_GIT_QUALIFICATION_REPORT_V1",
        "evidence_class": "REPRODUCIBLE_CI_TEST_ONLY_NOT_PROVENANCE_RECEIPT",
        "source_commit_sha": git("rev-parse", "HEAD"),
        "github_run_id": os.environ.get("GITHUB_RUN_ID"),
        "git_blobs": anchors,
        "case_count": len(rows),
        "pass_count": passed,
        "fail_count": EXPECTED_COUNT - passed,
        "adversarial_pass": benchmark["unknown_mixed_shared_fail_closed"],
        "unsafe_under_block": benchmark["unsafe_under_block"],
        "authorization": {"scoped_pass_authorized": False, "downstream_authorized": False, "production_authorized": False},
        "db_case_activation": "NOT_PERFORMED",
        "results": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="ig_ci50_qualification_report.json")
    args = parser.parse_args()
    try:
        report = evaluate()
    except (ValueError, subprocess.CalledProcessError, KeyError, OSError) as exc:
        print(f"FAIL_CLOSED:{exc}", file=sys.stderr)
        return 2
    Path(args.output).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"CI50 PASS {report['pass_count']}/{report['case_count']}; adversarial=10/10; downstream=DISABLED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
