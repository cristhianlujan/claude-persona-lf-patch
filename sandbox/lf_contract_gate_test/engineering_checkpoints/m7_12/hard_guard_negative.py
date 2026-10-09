#!/usr/bin/env python3
"""M7.12 adversarial hard-guard regression against the real Git candidate grader.

Both canonical Git sources are passed from the exact merged repository ref.
The runner executes the actual grader as a separate Python process, checks its
real exit status and error codes, and confirms a valid positive control passes.
Candidate-only: no database writes, Validator authority, or runtime activation.
"""
import argparse
import hashlib
import json
import subprocess
import sys

TEST_CODE = "ENG_M7_12_HARD_GUARD_NEGATIVE"


def git_blob_sha1(content):
    raw = content.encode("utf-8")
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--grader-source", required=True)
    parser.add_argument("--antipatterns-source", required=True)
    parser.add_argument("--grader-blob", required=True)
    parser.add_argument("--antipatterns-blob", required=True)
    args = parser.parse_args()

    for label, source, expected in (
        ("grader", args.grader_source, args.grader_blob),
        ("antipatterns", args.antipatterns_source, args.antipatterns_blob),
    ):
        if git_blob_sha1(source) != expected:
            raise AssertionError(f"Exact merged Git {label} blob mismatch")

    cases = [
        ("B01", "Remediación abierta.", {
            "evaluation_outcome": "NEGATIVE_CONFIRMED",
            "evidence_examined": ["canonical rule"], "evidence_found": [],
            "exact_gap": "Scope-bound source missing", "cause_type": "CANONICAL_SOURCE_ABSENT",
            "remediation_action": ["Remediación abierta."],
            "do_not_do": ["No inference"], "close_when": ["Evidence readback required"],
            "next_owner": "RESOLVER", "human_decision_required": False,
        }, "GENERIC_TERMINAL_REMEDIATION"),
        ("B05", "No hay permisos asociados.", {
            "evaluation_outcome": "NOT_APPLICABLE",
            "positive_authority_ref": "", "scope_match": True,
            "reason": "No hay permisos asociados.",
        }, "NOT_APPLICABLE_WITHOUT_POSITIVE_AUTHORITY"),
        ("B10", "cuando se cierre el gap", {
            "evaluation_outcome": "NEGATIVE_CONFIRMED",
            "evidence_examined": ["canonical rule"], "evidence_found": [],
            "exact_gap": "Scope-bound source missing", "cause_type": "CANONICAL_SOURCE_ABSENT",
            "remediation_action": ["Resolve explicit reference"],
            "do_not_do": ["No invented source"],
            "close_when": ["cuando se cierre el gap"],
            "next_owner": "RESOLVER", "human_decision_required": False,
        }, "TAUTOLOGICAL_CLOSE_CONDITION"),
        ("B11", "cuando esté listo", {
            "evaluation_outcome": "NEGATIVE_CONFIRMED",
            "evidence_examined": ["canonical rule"], "evidence_found": ["evidencia encontrada"],
            "exact_gap": "falta información", "cause_type": "GOVERNANCE_EVIDENCE_MISSING",
            "remediation_action": ["revisar", "completar", "validar"],
            "do_not_do": ["no equivocarse"],
            "close_when": ["cuando esté listo"],
            "next_owner": "RESOLVER", "human_decision_required": False,
        }, "GENERIC_TERMINAL_REMEDIATION"),
    ]

    observed = []
    for case_id, needle, fixture, guard in cases:
        section = args.antipatterns_source.split("## " + case_id + " — ", 1)
        if len(section) != 2 or needle not in section[1].split("\n## ", 1)[0]:
            raise AssertionError("Antipattern canonical content absent: " + case_id)
        actual = subprocess.run([sys.executable, "-c", args.grader_source, "-"],
                                input=json.dumps(fixture), capture_output=True,
                                text=True, timeout=15)
        result = json.loads(actual.stdout.strip())
        if actual.returncode != 1 or result.get("verdict") != "FAIL_HARD_GUARD" or guard not in result.get("errors", []):
            raise AssertionError(f"{case_id}: expected real FAIL_HARD_GUARD {guard}, got {actual.returncode} {result}")
        observed.append({"case": case_id, "expected": guard, "verdict": result["verdict"]})

    positive = {
        "evaluation_outcome": "POSITIVE", "evidence_chain": ["valid current source"],
        "authority_basis": ["active source and exact scope"], "resolved_requirements": ["field reference"],
        "unresolved_required": [], "close_reason": "explicit current authority verified",
    }
    ctrl = subprocess.run([sys.executable, "-c", args.grader_source, "-"],
                          input=json.dumps(positive), capture_output=True,
                          text=True, timeout=15)
    positive_result = json.loads(ctrl.stdout.strip())
    if ctrl.returncode != 0 or positive_result.get("verdict") != "PASS":
        raise AssertionError("Positive control was not admitted by the same grader")

    print(json.dumps({
        "test_code": TEST_CODE, "status": "PASS",
        "observed": {
            "test_passed": True, "test_exit_code": 0,
            "semantic_authority_bound": True, "adversarial_case_executed": True,
        },
        "evidence": {"actual_negative_tests": observed, "positive_control": "PASS",
                     "grader_blob": args.grader_blob,
                     "antipatterns_blob": args.antipatterns_blob},
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(json.dumps({"test_code": TEST_CODE, "status": "FAIL",
                          "reason": str(exc)}), file=sys.stderr)
        sys.exit(1)
