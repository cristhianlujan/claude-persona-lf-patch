#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

PREFLIGHT_SCHEMA = "S26_PROFILE_UPDATE_LEARNING_PREFLIGHT_V1"
MINIMUM_CODES = {
    "PROFILES-EKB-PREFLIGHT-OMISSION-001",
    "GOV-024",
    "AUD-018",
    "CI-014",
}
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PROFILE_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_]{0,79}$")


def _block(code: str, blockers: list[str]) -> None:
    if code not in blockers:
        blockers.append(code)


def _repo_head(repo_root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            text=True, capture_output=True, check=False, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    head = result.stdout.strip()
    return head if result.returncode == 0 and SHA40_RE.fullmatch(head) else None


def evaluate_learning_preflight(
    payload: Any,
    profile_slug: str,
    *,
    repo_root: Path | None = None,
    current_revision: str | None = None,
) -> dict[str, Any]:
    blockers: list[str] = []
    matched: list[str] = []
    checks: list[dict[str, Any]] = []
    executed_count = 0
    na_count = 0

    if not PROFILE_SLUG_RE.fullmatch(profile_slug):
        _block("PROFILE_TARGET_INVALID", blockers)
    if not isinstance(payload, dict):
        _block("LEARNING_PREFLIGHT_PAYLOAD_INVALID", blockers)
        payload = {}

    if payload.get("schema") != PREFLIGHT_SCHEMA:
        _block("LEARNING_PREFLIGHT_SCHEMA_INVALID", blockers)
    if payload.get("profile_slug") != profile_slug:
        _block("LEARNING_PREFLIGHT_PROFILE_MISMATCH", blockers)

    if current_revision is None and repo_root is not None:
        current_revision = _repo_head(repo_root.resolve())
    if not isinstance(current_revision, str) or not SHA40_RE.fullmatch(current_revision):
        _block("CURRENT_REVISION_UNAVAILABLE", blockers)
        current_revision = ""

    repository = payload.get("repository")
    if not isinstance(repository, str) or not repository.strip():
        _block("REPOSITORY_IDENTITY_MISSING", blockers)
    if payload.get("current_main_sha") != current_revision:
        _block("STALE_MAIN_REVISION", blockers)

    ekb = payload.get("ekb_preflight")
    if not isinstance(ekb, dict):
        _block("EKB_PREFLIGHT_MISSING", blockers)
        ekb = {}
    if ekb.get("status") != "EKB_PREFLIGHT_COMPLETED":
        _block("EKB_PREFLIGHT_NOT_COMPLETED", blockers)
    if ekb.get("source") != "public.lf_error_knowledge":
        _block("EKB_SOURCE_NOT_CANONICAL", blockers)

    raw_codes = ekb.get("matched_error_codes")
    if not isinstance(raw_codes, list) or not raw_codes or not all(isinstance(code, str) and code for code in raw_codes):
        _block("EKB_MATCHED_CODES_INVALID", blockers)
    else:
        matched = list(raw_codes)
        if len(set(matched)) != len(matched):
            _block("EKB_MATCHED_CODES_DUPLICATED", blockers)
        missing_min = sorted(MINIMUM_CODES.difference(matched))
        if missing_min:
            _block("EKB_MINIMUM_CONTROLS_MISSING", blockers)

    raw_rules = ekb.get("matched_prevention_rules")
    if not isinstance(raw_rules, list):
        _block("EKB_MATCHED_PREVENTION_RULES_MISSING", blockers)
        raw_rules = []
    rule_map: dict[str, dict[str, Any]] = {}
    for raw in raw_rules:
        if not isinstance(raw, dict):
            _block("EKB_PREVENTION_RULE_INVALID", blockers)
            continue
        code = raw.get("code")
        if not isinstance(code, str) or not code:
            _block("EKB_PREVENTION_RULE_CODE_INVALID", blockers)
            continue
        if code in rule_map:
            _block("EKB_PREVENTION_RULE_DUPLICATED", blockers)
            continue
        rule_map[code] = raw
        if code not in matched:
            _block("EKB_PREVENTION_RULE_UNMATCHED_CODE", blockers)
        if not isinstance(raw.get("rule"), str) or not raw.get("rule").strip():
            _block(f"EKB_PREVENTION_RULE_TEXT_MISSING:{code}", blockers)
        if not isinstance(raw.get("source_ref"), str) or not raw.get("source_ref"):
            _block(f"EKB_PREVENTION_RULE_SOURCE_MISSING:{code}", blockers)

    for code in matched:
        if code not in rule_map:
            _block(f"EKB_PREVENTION_RULE_UNMAPPED:{code}", blockers)

    raw_checks = ekb.get("prevention_checks")
    if not isinstance(raw_checks, list):
        _block("EKB_PREVENTION_CHECKS_MISSING", blockers)
        raw_checks = []

    check_map: dict[str, dict[str, Any]] = {}
    for raw in raw_checks:
        if not isinstance(raw, dict):
            _block("EKB_PREVENTION_CHECK_INVALID", blockers)
            continue
        code = raw.get("code")
        if not isinstance(code, str) or not code:
            _block("EKB_PREVENTION_CHECK_CODE_INVALID", blockers)
            continue
        if code in check_map:
            _block("EKB_PREVENTION_CHECK_DUPLICATED", blockers)
            continue
        check_map[code] = raw
        checks.append(raw)
        if code not in matched:
            _block("EKB_PREVENTION_CHECK_UNMATCHED_CODE", blockers)

    for code in matched:
        item = check_map.get(code)
        if item is None:
            _block(f"EKB_PREVENTION_UNMAPPED:{code}", blockers)
            continue
        status = item.get("status")
        source_ref = item.get("source_ref")
        if not isinstance(source_ref, str) or not source_ref:
            _block(f"EKB_PREVENTION_SOURCE_MISSING:{code}", blockers)
        if status == "PASS":
            required = (
                item.get("executed") is True
                and item.get("exit_code") == 0
                and item.get("result") in {"PASS", "SUCCESS"}
                and isinstance(item.get("test_id"), str) and bool(item.get("test_id"))
                and isinstance(item.get("evidence_sha256"), str)
                and bool(SHA256_RE.fullmatch(item.get("evidence_sha256")))
            )
            if not required:
                _block(f"EKB_PREVENTION_EXECUTION_RECEIPT_INVALID:{code}", blockers)
            else:
                executed_count += 1
        elif status == "NOT_APPLICABLE":
            if not isinstance(item.get("reason"), str) or not item.get("reason").strip():
                _block(f"EKB_PREVENTION_NA_REASON_MISSING:{code}", blockers)
            else:
                na_count += 1
        else:
            _block(f"EKB_PREVENTION_STATUS_INVALID:{code}", blockers)

    binding = payload.get("execution_binding")
    if not isinstance(binding, dict):
        _block("EXECUTION_BINDING_MISSING", blockers)
        binding = {}
    if binding.get("operation_code") != "ACTUALIZACION_PERFIL_LF":
        _block("EXECUTION_OPERATION_MISMATCH", blockers)
    if binding.get("target_type") != "PROFILE":
        _block("EXECUTION_TARGET_TYPE_MISMATCH", blockers)
    expected_target = f"profiles/{profile_slug}"
    if binding.get("target_path") != expected_target:
        _block("EXECUTION_TARGET_PATH_MISMATCH", blockers)
    if not isinstance(binding.get("execution_id"), str) or not binding.get("execution_id"):
        _block("EXECUTION_ID_MISSING", blockers)
    if binding.get("status") != "IN_PROGRESS":
        _block("EXECUTION_NOT_ACTIVE_PREWRITE", blockers)
    if binding.get("step_id") != "pre_write_execution_binding_gate":
        _block("PREWRITE_STEP_MISMATCH", blockers)
    if binding.get("step_status") != "STEP_PASS_WITH_EVIDENCE":
        _block("PREWRITE_STEP_NOT_PASS", blockers)
    if binding.get("pre_write_gate_passed") is not True:
        _block("PREWRITE_GATE_NOT_PASSED", blockers)
    if binding.get("execution_bound_to_target_before_change") is not True:
        _block("EXECUTION_NOT_BOUND_BEFORE_CHANGE", blockers)

    bound = binding.get("bound_revision")
    if not isinstance(bound, dict):
        _block("BOUND_REVISION_MISSING", blockers)
        bound = {}
    if bound.get("path") != expected_target:
        _block("BOUND_REVISION_TARGET_MISMATCH", blockers)
    if bound.get("revision_sha") != current_revision:
        _block("BOUND_REVISION_STALE", blockers)
    if repository and bound.get("repo") != repository:
        _block("BOUND_REVISION_REPOSITORY_MISMATCH", blockers)

    write_plan = binding.get("write_plan")
    if not isinstance(write_plan, dict):
        _block("WRITE_PLAN_MISSING", blockers)
        write_plan = {}
    allowed_paths = write_plan.get("allowed_paths")
    expected_scope = f"{expected_target}/**"
    if not isinstance(allowed_paths, list) or not allowed_paths:
        _block("WRITE_SCOPE_MISSING", blockers)
    elif any(path != expected_scope for path in allowed_paths):
        _block("WRITE_SCOPE_ESCAPE", blockers)
    if write_plan.get("automatic_runtime_activation") is not False:
        _block("RUNTIME_ACTIVATION_BOUNDARY_MISSING", blockers)
    if write_plan.get("production_change") is not False:
        _block("PRODUCTION_BOUNDARY_MISSING", blockers)

    covered = sum(1 for code in matched if code in check_map)
    coverage = round(covered * 100 / len(matched), 1) if matched else 0.0
    metrics = {
        "matched_error_count": len(matched),
        "matched_prevention_rule_count": len(rule_map),
        "prevention_check_count": len(check_map),
        "executed_prevention_count": executed_count,
        "not_applicable_count": na_count,
        "learning_coverage_pct": coverage,
        "blocking_count": len(blockers),
    }
    passed = not blockers
    return {
        "schema": "S26_PROFILE_UPDATE_LEARNING_PREFLIGHT_EVALUATION_V1",
        "input_schema": PREFLIGHT_SCHEMA,
        "profile_slug": profile_slug,
        "status": "PASS" if passed else "BLOCKED",
        "write_preflight_authorized": passed,
        "blocking_codes": sorted(blockers),
        "matched_error_codes": matched,
        "metrics": metrics,
        "current_revision": current_revision or None,
        "target_code_execution_performed": False,
        "reusable_for_new_run": False,
        "automatic_runtime_activation": False,
        "production_activation": False,
    }


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("usage: evaluate_s26_learning_preflight.py <profile_slug> <preflight_json> [repo_root]", file=sys.stderr)
        return 2
    slug = sys.argv[1]
    preflight_path = Path(sys.argv[2]).resolve()
    repo = Path(sys.argv[3]).resolve() if len(sys.argv) == 4 else Path(__file__).resolve().parents[3]
    try:
        payload = json.loads(preflight_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        payload = None
    result = evaluate_learning_preflight(payload, slug, repo_root=repo)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 3


if __name__ == "__main__":
    raise SystemExit(main())
