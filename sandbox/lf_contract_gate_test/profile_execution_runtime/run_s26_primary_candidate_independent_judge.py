#!/usr/bin/env python3
"""Independent, fail-closed S26 capability panel over a captured candidate RAW.

This fixed-task panel does not replace the complete profile obligation manifest,
establish operational parity, change authority, or authorize downstream work.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from github_actions_semantic_judge import (
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
    SEMANTIC_MODEL_ID,
    SEMANTIC_MODEL_SHA256,
)
from validate_profile_execution import canonical_json_sha256


CHECKS = (
    (
        "S26_PHYSICAL_MECHANIC_AND_PASSIVE_CUE",
        "The treatment must combine an implementable physical horizontal-overflow mechanic "
        "with a passive discoverability cue; a tooltip alone is not the overflow mechanic.",
        "Does the complete decision comply with this rule?",
    ),
    (
        "S26_PRESERVE_EXISTING_TABLE",
        "The decision must preserve existing filters, all table columns, row actions, "
        "pagination, table semantics and business rules; it must not hide or replace them.",
        "Does the complete decision directly preserve the required existing behavior?",
    ),
    (
        "S26_IMPLEMENTATION_USABLE",
        "The implementation must specify a concrete overflow mechanic and its cue with "
        "implementation target, behavior and usable property/value; describing only tooltip "
        "content is insufficient.",
        "Does the complete decision comply with this implementation rule?",
    ),
    (
        "S26_SUBORDINATE_AND_NON_OBSCURING",
        "The cue and mechanic must remain subordinate to table content and row actions and "
        "must not obscure or replace their meaning.",
        "Does the complete decision establish compliance with this rule?",
    ),
    (
        "S26_EXCLUSIONS_CONSISTENT",
        "Hard exclusions must contain rejected alternatives only and must not repeat or "
        "contradict the selected treatment.",
        "Are the exclusions consistent with the selected treatment?",
    ),
    (
        "S26_GROUNDED_NO_INVENTION",
        "The decision may choose a novel overflow mechanic, but it must not invent an "
        "unsupported pixel value, percentage, row-count, pagination trigger, breakpoint, "
        "control, design token, canonical pattern or business rule. The only supplied "
        "quantitative density bound is one passive cue per overflowing table viewport and "
        "zero added controls per row.",
        "Is every asserted limit or value grounded by this rule?",
    ),
    (
        "S26_COMPLETE_SELF_CONTAINED_FIELDS",
        "Every field must be a complete, self-contained statement; no string may end "
        "mid-list, mid-condition, or mid-clause, and enumerations must not contain a "
        "dangling separator or omit their stated endpoint.",
        "Are all fields complete and self-contained under this rule?",
    ),
)


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise RuntimeError(f"CANDIDATE_{key.upper()}_MISSING")
    return value


def load_candidate_capture(path: Path) -> tuple[dict[str, Any], str]:
    try:
        capture = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError("CANDIDATE_CAPTURE_INVALID_JSON") from exc
    if not isinstance(capture, dict) or capture.get("capture_schema") != "S26_PRIMARY_CANDIDATE_CAPTURE_V1":
        raise RuntimeError("CANDIDATE_CAPTURE_SCHEMA_MISMATCH")
    if capture.get("marker_found") is not True or capture.get("benchmark_process_exit_code") != 0:
        raise RuntimeError("CANDIDATE_CAPTURE_PROCESS_NOT_NOMINAL")
    result = capture.get("result")
    if not isinstance(result, dict):
        raise RuntimeError("CANDIDATE_RESULT_MISSING")
    if result.get("contract_gate", {}).get("status") != "PASS":
        raise RuntimeError("CANDIDATE_CONTRACT_NOT_PASS")
    if result.get("semantic_gate", {}).get("status") != "PASS":
        raise RuntimeError("CANDIDATE_DETERMINISTIC_SEMANTIC_NOT_PASS")
    if result.get("production_mutation") is not False or result.get("promotion_authorized") is not False:
        raise RuntimeError("CANDIDATE_SCOPE_ESCALATION_FORBIDDEN")
    if result.get("paid_provider_call_executed") is not False or result.get("api_cost_incurred") is not False:
        raise RuntimeError("CANDIDATE_ZERO_COST_ASSERTION_FAILED")
    if result.get("candidate_model_released_after_run") is not True:
        raise RuntimeError("CANDIDATE_MODEL_NOT_RELEASED")
    if result.get("github_run_id") != os.environ.get("GITHUB_RUN_ID", ""):
        raise RuntimeError("CANDIDATE_GITHUB_RUN_BINDING_MISMATCH")
    if result.get("github_sha") != os.environ.get("GITHUB_SHA", ""):
        raise RuntimeError("CANDIDATE_GITHUB_SHA_BINDING_MISMATCH")
    raw_output = _required_string(result, "raw_output")
    try:
        parsed_raw = json.loads(raw_output)
    except json.JSONDecodeError as exc:
        raise RuntimeError("CANDIDATE_RAW_OUTPUT_INVALID_JSON") from exc
    if parsed_raw != result.get("output"):
        raise RuntimeError("CANDIDATE_RAW_OUTPUT_BINDING_MISMATCH")
    return result, raw_output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-capture", type=Path, required=True)
    parser.add_argument("--result-path", type=Path, required=True)
    args = parser.parse_args()

    candidate, raw_output = load_candidate_capture(args.candidate_capture)
    evidence_text = json.dumps(candidate["output"], ensure_ascii=False, sort_keys=True)
    work_root = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    work_dir = work_root / "s26-primary-candidate-independent-judge"
    verifier = GitHubHostedSemanticMiniJudgeVerifier()
    results: list[dict[str, Any]] = []
    with GitHubHostedSemanticMiniJudge(work_dir=work_dir) as judge:
        for check_id, rule, question in CHECKS:
            check = {
                "check_id": check_id,
                "check_type": "SEMANTIC_RELATION",
                "rule": rule,
                "evidence": evidence_text,
                "question": question,
            }
            classification, execution_evidence = judge.classify(check)
            verification = verifier.verify(
                check=check,
                result=classification,
                evidence=execution_evidence,
                adapter=judge,
            )
            results.append(
                {
                    "check_id": check_id,
                    "rule_sha256": _sha256_text(rule),
                    "verdict": classification.verdict,
                    "reason_code": classification.reason_code,
                    "execution_evidence": execution_evidence,
                    "verification": verification,
                }
            )

    all_comply = all(item["verdict"] == "COMPLIES" for item in results)
    all_verified = all(item["verification"].get("verified") is True for item in results)
    status = "PASS" if all_comply and all_verified else "FAIL"
    payload = {
        "result_schema": "S26_PRIMARY_CANDIDATE_INDEPENDENT_JUDGE_V1",
        "status": status,
        "evaluation_scope": "SEVEN_ATOMIC_SEMANTIC_RELATIONS_FAIL_CLOSED",
        "complete_profile_obligation_manifest_executed": False,
        "operational_parity": False,
        "github_attested": True,
        "github_run_id": os.environ.get("GITHUB_RUN_ID", ""),
        "github_sha": os.environ.get("GITHUB_SHA", ""),
        "candidate_binding": {
            "candidate_code": candidate.get("candidate_code"),
            "candidate_head": candidate.get("candidate_head"),
            "model_id": candidate.get("model_id"),
            "model_sha256": candidate.get("model_sha256"),
            "prompt_policy": candidate.get("prompt_policy"),
            "revision_architecture": candidate.get("revision_architecture"),
            "raw_output_sha256": _sha256_text(raw_output),
            "result_sha256": canonical_json_sha256(candidate),
        },
        "judge_binding": {
            "model_id": SEMANTIC_MODEL_ID,
            "model_sha256": SEMANTIC_MODEL_SHA256,
        },
        "checks": results,
        "contract_gate": candidate["contract_gate"],
        "deterministic_semantic_gate": candidate["semantic_gate"],
        "downstream_authorized": False,
        "authority_changed": False,
        "production_mutation": False,
        "promotion_authorized": False,
        "paid_provider_call_executed": False,
        "api_cost_incurred": False,
    }
    args.result_path.parent.mkdir(parents=True, exist_ok=True)
    args.result_path.write_text(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "S26_PRIMARY_CANDIDATE_INDEPENDENT_JUDGE="
        + json.dumps(payload, ensure_ascii=False, sort_keys=True),
        flush=True,
    )
    if status == "PASS":
        print("S26_PRIMARY_CANDIDATE_INDEPENDENT_JUDGE_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_PRIMARY_CANDIDATE_INDEPENDENT_JUDGE_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
