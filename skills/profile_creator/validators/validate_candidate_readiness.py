#!/usr/bin/env python3
import copy
import json
import sys
from pathlib import Path

import validate_candidate_consistency as consistency
import validate_candidate_depth as depth

READY = "DEPTH_READY_FOR_SEMANTIC_REVIEW"
REPAIR = "RETURN_TO_WORKER_FOR_SELF_REPAIR"
LEGACY_STATUS_OVERFIT = "OUTPUT_SCHEMA_STATUS_NOT_CLOSED"


def is_legacy_status_only_block(code):
    return (
        code == "OUTPUT_SCHEMA_STATUS_NOT_CLOSED"
        or code.startswith("EVAL_EXPECTED_STATUS_MISSING:")
        or code in {"EVAL_POSITIVE_CASE_REQUIRED", "EVAL_NEGATIVE_CASES_REQUIRED"}
    )


def generic_discriminator_contract_is_clean(consistency_blocking):
    prefixes = (
        "OUTPUT_DISCRIMINATOR_",
        "EVAL_UNDECLARED_DISCRIMINATOR_VALUE:",
        "EVAL_EXPECTED_DISCRIMINATOR_MISSING:",
        "EXAMPLE_UNDECLARED_DISCRIMINATOR_VALUE:",
        "EXAMPLE_DISCRIMINATOR_MISSING:",
    )
    return not any(code.startswith(prefixes) for code in consistency_blocking)


def merged_validation(pack):
    depth_blocking, depth_warnings = depth.validate_candidate(pack)
    consistency_blocking, consistency_warnings = consistency.validate_candidate(pack)

    # GOV-021 depth validation historically assumed every generated worker used
    # root `status` and `expected_status`. Strong LF profiles use other closed
    # discriminators such as `output_type` / `self_verdict`. The aggregate gate
    # suppresses only those status-name assumptions when the generic contract is
    # independently clean; every other GOV-021 depth blocker is preserved.
    if generic_discriminator_contract_is_clean(consistency_blocking):
        depth_blocking = [code for code in depth_blocking if not is_legacy_status_only_block(code)]

    blocking = []
    for code in depth_blocking + consistency_blocking:
        if code not in blocking:
            blocking.append(code)
    warnings = []
    for item in depth_warnings + consistency_warnings:
        if item not in warnings:
            warnings.append(item)
    if not any(is_legacy_status_only_block(code) for code in blocking):
        warnings.append("GENERIC_CLOSED_OUTPUT_DISCRIMINATOR_ACCEPTED")
    return blocking, warnings, depth_blocking, consistency_blocking


def validate_file(path):
    try:
        pack = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        return {
            "status": REPAIR,
            "validation_scope": "DETERMINISTIC_READINESS_DEPTH_AND_CONSISTENCY",
            "semantic_quality_review": "NOT_EXECUTED",
            "behavioral_eval_status": "NOT_EXECUTED",
            "blocking_codes": [f"CANDIDATE_READ_ERROR:{exc}"],
            "warnings": [],
        }
    blocking, warnings, depth_blocking, consistency_blocking = merged_validation(pack)
    return {
        "status": READY if not blocking else REPAIR,
        "validation_scope": "DETERMINISTIC_READINESS_DEPTH_AND_CONSISTENCY",
        "semantic_quality_review": "NOT_EXECUTED",
        "behavioral_eval_status": "NOT_EXECUTED",
        "component_gates": {
            "producer_depth": "PASS" if not depth_blocking else "FAIL",
            "cross_artifact_consistency": "PASS" if not consistency_blocking else "FAIL",
        },
        "blocking_codes": blocking,
        "warnings": warnings,
    }


def self_test(root):
    root = Path(root)
    fixture = root / "fixtures/architecture_consistency/positive_candidate_pack.json"
    positive = json.loads(fixture.read_text(encoding="utf-8"))
    cases = []

    def run(name, pack, expected_ready, expected_code=None):
        blocking, warnings, _, _ = merged_validation(pack)
        ready = not blocking
        aligned = ready == expected_ready and (expected_code is None or expected_code in blocking)
        cases.append({"case": name, "aligned": aligned, "blocking_codes": blocking, "warnings": warnings})

    run("status_discriminator_positive", positive, True)
    run("non_status_discriminator_positive", consistency.mutate_non_status_discriminator(positive), True)

    mismatch = copy.deepcopy(positive)
    evals = json.loads(mismatch["files"]["evals/eval_matrix.json"])
    evals["cases"][0]["expected_status"] = "UNDECLARED_MODE"
    mismatch["files"]["evals/eval_matrix.json"] = json.dumps(evals, indent=2)
    run("cross_artifact_mismatch_rejected", mismatch, False)

    no_validator = copy.deepcopy(positive)
    no_validator["files"].pop("validators/validate_pack.py", None)
    run("missing_executable_validator_rejected", no_validator, False, "EXECUTABLE_PROFILE_VALIDATOR_REQUIRED")

    failed = [case["case"] for case in cases if not case["aligned"]]
    return {
        "status": "PASS" if not failed else "FAIL",
        "validation_scope": "DETERMINISTIC_READINESS_SELF_TEST",
        "semantic_quality_review": "NOT_EXECUTED",
        "behavioral_eval_status": "NOT_EXECUTED",
        "cases": cases,
        "aligned": len(cases) - len(failed),
        "total": len(cases),
        "failed_cases": failed,
    }


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        root = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path.cwd()
        result = self_test(root)
        print(json.dumps(result, indent=2))
        return 0 if result["status"] == "PASS" else 1
    if len(sys.argv) < 2:
        print("usage: validate_candidate_readiness.py <candidate.json> | --self-test <profile_creator_root>", file=sys.stderr)
        return 2
    result = validate_file(Path(sys.argv[1]))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == READY else 1


if __name__ == "__main__":
    raise SystemExit(main())
