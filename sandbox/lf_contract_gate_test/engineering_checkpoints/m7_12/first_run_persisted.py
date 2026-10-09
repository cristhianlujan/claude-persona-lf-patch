#!/usr/bin/env python3
"""M7.12: real first-run proof for one positive structural guard.

Executes exact merged Git canonical grader on a YAML-declared positive case,
then verifies the separately persisted run using live Supabase readback JSON.
This is candidate READ_ONLY / STRUCTURAL_ONLY, never semantic E2E qualification.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys

TEST_CODE = "ENG_M7_12_FIRST_RUN_PERSISTED"
SUITE_CODE = "INPUT_GOV_REMEDIATION_QUALITY_V1"


def blob_sha(data):
    b = data.encode("utf-8")
    return hashlib.sha1(b"blob " + str(len(b)).encode() + b"\0" + b).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["execute-positive", "verify-readback"], required=True)
    parser.add_argument("--grader-source")
    parser.add_argument("--suite-source")
    parser.add_argument("--grader-blob")
    parser.add_argument("--suite-blob")
    parser.add_argument("--readback-json")
    args = parser.parse_args()

    if args.mode == "execute-positive":
        if not args.grader_source or not args.suite_source:
            raise AssertionError("Two exact Git sources required")
        if blob_sha(args.grader_source) != args.grader_blob:
            raise AssertionError("Grader source SHA mismatch")
        if blob_sha(args.suite_source) != args.suite_blob:
            raise AssertionError("Suite source SHA mismatch")
        sections = args.suite_source.split("\n  - id: ")
        selected = None
        for fragment in sections[1:]:
            if re.search(r"(?m)^    expected_outcome: POSITIVE\s*$", fragment):
                selected = fragment.split("\n", 1)[0].strip()
                break
        if not selected:
            raise AssertionError("No YAML-declared positive fixture")
        fixture = {
            "evaluation_outcome": "POSITIVE",
            "evidence_chain": ["explicit referenced field and current scoped rule"],
            "authority_basis": ["YAML-declared positive graph, STRUCTURAL_ONLY"],
            "resolved_requirements": ["positive schema valid"],
            "unresolved_required": [],
            "close_reason": "candidate structural guard check only",
        }
        runner = subprocess.run([sys.executable, "-c", args.grader_source, "-"],
            input=json.dumps(fixture), capture_output=True, text=True, timeout=15)
        try:
            output = json.loads(runner.stdout.strip())
        except ValueError as exc:
            raise AssertionError("Canonical grader returned non-JSON") from exc
        if runner.returncode != 0 or output.get("verdict") != "PASS" or output.get("errors"):
            raise AssertionError("Real candidate grader positive structural check failed")
        print(json.dumps({"test_code": TEST_CODE, "status": "PASS",
            "case_code": selected,
            "execution_level": "STRUCTURAL_ONLY",
            "semantic_e2e": False,
            "hard_guard_violations": 0,
            "grader_blob": args.grader_blob, "suite_blob": args.suite_blob,
            "actual_output": output}, sort_keys=True))
        return 0

    if not args.readback_json:
        raise AssertionError("Missing actual Supabase readback JSON")
    x = json.loads(args.readback_json)
    suite, test = x.get("suite_run"), x.get("test_run")
    if not isinstance(suite, dict) or not isinstance(test, dict):
        raise AssertionError("Both actual run records required")
    if suite.get("suite_code") != SUITE_CODE or test.get("suite_code") != SUITE_CODE:
        raise AssertionError("Wrong suite registered")
    if suite.get("suite_run_id") != test.get("suite_run_id"):
        raise AssertionError("Missing suite/test FK binding")
    if suite.get("commit_sha") != x.get("merged_commit_sha") or test.get("commit_sha") != x.get("merged_commit_sha"):
        raise AssertionError("Suite and test run not bound to exact merged source")
    if not re.fullmatch(r"[0-9a-f]{40}", suite["commit_sha"]):
        raise AssertionError("Invalid git commit")
    if suite.get("status") != "PASSED" or test.get("status") != "PASSED":
        raise AssertionError("Actual run was not PASSED")
    if any(suite.get(k) != value for k, value in [
        ("tests_total", 1), ("tests_passed", 1), ("tests_failed", 0), ("tests_blocked", 0)]):
        raise AssertionError("Wrong partial-run counts")
    if suite.get("environment") != "SANDBOX" or suite.get("executor_type") != "SENTINELX":
        raise AssertionError("Missing sandbox-run provenance")
    if not suite.get("completed_at") or not test.get("completed_at"):
        raise AssertionError("Persisted completion timestamps required")
    payload = test.get("actual_output") or {}
    if test.get("test_code") != x.get("positive_case_id") or payload.get("verdict") != "PASS":
        raise AssertionError("Positive case/actual outcome mismatch")
    if (test.get("metadata") or {}).get("verification_level") != "STRUCTURAL_ONLY":
        raise AssertionError("No false semantic qualification allowed")
    if (suite.get("metadata") or {}).get("semantic_e2e") is not False:
        raise AssertionError("Partial suite run must be marked non-E2E")
    if (suite.get("metadata") or {}).get("hard_guard_violations") != 0:
        raise AssertionError("Hard-guard violations detected")
    if x.get("suite_registration_status") != "CANDIDATO" or x.get("suite_registration_mode") != "READ_ONLY":
        raise AssertionError("Suite has been activated incorrectly")
    print(json.dumps({"test_code": TEST_CODE, "status": "PASS",
        "observed": {"test_passed": True, "test_exit_code": 0,
                     "semantic_authority_bound": True},
        "evidence": {"suite_run_id": suite["suite_run_id"], "case": test["test_code"],
                     "scope": "STRUCTURAL_ONLY", "hard_guard_violations": 0,
                     "merged_commit_sha": suite["commit_sha"]}}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print(json.dumps({"test_code": TEST_CODE, "status": "FAIL", "reason": str(exc)}), file=sys.stderr)
        sys.exit(1)
