#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

PASS = "PASS_TO_MATERIAL_WORK"
FAIL = "FAIL_CLOSED_BEFORE_MATERIAL_WORK"
SHA40 = re.compile(r"^[0-9a-f]{40}$")

REQUIRED_TOP = {
    "work_package_id", "strategy_id", "lane_id", "capability_id", "version",
    "owner", "worker", "judge", "currentness", "ownership", "scope",
    "capability_binding", "pre_execution_assurance", "assertions", "evidence",
    "frontier", "closure",
}

MANDATORY_FORBIDDEN = {
    "MUTATE_S30_INTERNALS",
    "MUTATE_S26_INTERNALS",
    "ENABLE_PRODUCTION",
    "PROMOTE_GOLDEN",
    "MERGE_MAIN",
}

MANDATORY_PREFLIGHT = {
    "CURRENTNESS_RESOLVED",
    "SOURCE_AUTHORITY_RESOLVED",
    "EKB_APPLICABILITY_RESOLVED",
    "OWNERSHIP_COLLISION_FREE",
    "SCHEMAS_CONTRACTS_RESOLVED",
    "TOOLS_FUNCTIONS_ADAPTERS_RESOLVED",
    "EVIDENCE_READBACK_RESOLVED",
    "ASSERTIONS_ENUMERATED",
    "NEGATIVE_PATH_DEFINED",
}


def _list_of_strings(value: Any, *, nonempty: bool = False) -> bool:
    return isinstance(value, list) and (not nonempty or bool(value)) and all(isinstance(x, str) and x for x in value)


def validate(wp: dict[str, Any]) -> dict[str, Any]:
    failures: list[str] = []

    missing = sorted(REQUIRED_TOP - set(wp))
    if missing:
        failures.append("MISSING_TOP_LEVEL:" + ",".join(missing))

    if wp.get("strategy_id") != "S31":
        failures.append("STRATEGY_NOT_S31")
    if not isinstance(wp.get("lane_id"), str) or not re.fullmatch(r"S31-[A-H]", wp["lane_id"]):
        failures.append("LANE_INVALID")
    if wp.get("version") != "v0.1-bootstrap":
        failures.append("VERSION_INVALID")

    currentness = wp.get("currentness") or {}
    if not SHA40.fullmatch(str(currentness.get("base_main_sha", ""))):
        failures.append("BASE_MAIN_SHA_INVALID")
    if currentness.get("stale_action") != FAIL:
        failures.append("STALE_ACTION_NOT_FAIL_CLOSED")
    if currentness.get("currentness_policy") not in {"EXACT_HEAD", "EXACT_SOURCE_REVISION", "FROZEN_SNAPSHOT"}:
        failures.append("CURRENTNESS_POLICY_INVALID")
    if not _list_of_strings(currentness.get("source_snapshot_refs"), nonempty=True):
        failures.append("SOURCE_SNAPSHOT_REFS_MISSING")
    if not _list_of_strings(currentness.get("authority_refs"), nonempty=True):
        failures.append("AUTHORITY_REFS_MISSING")

    ownership = wp.get("ownership") or {}
    if ownership.get("principle") != "ONE_CAUSAL_CHAIN_ONE_ACTIVE_WRITER":
        failures.append("OWNERSHIP_PRINCIPLE_INVALID")
    if not _list_of_strings(ownership.get("active_writer_scope"), nonempty=True):
        failures.append("ACTIVE_WRITER_SCOPE_MISSING")
    if not _list_of_strings(ownership.get("collision_checks"), nonempty=True):
        failures.append("COLLISION_CHECKS_MISSING")

    scope = wp.get("scope") or {}
    write_scope = scope.get("allowed_write_scope")
    if not _list_of_strings(write_scope, nonempty=True):
        failures.append("WRITE_SCOPE_MISSING")
    else:
        for path in write_scope:
            if not path.startswith("sandbox/lf_contract_gate_test/s31_"):
                failures.append("WRITE_SCOPE_ESCAPES_S31:" + path)
    forbidden = set(scope.get("forbidden_actions") or [])
    missing_forbidden = sorted(MANDATORY_FORBIDDEN - forbidden)
    if missing_forbidden:
        failures.append("MANDATORY_FORBIDDEN_MISSING:" + ",".join(missing_forbidden))

    binding = wp.get("capability_binding") or {}
    if not _list_of_strings(binding.get("required_capabilities"), nonempty=True):
        failures.append("REQUIRED_CAPABILITIES_MISSING")
    unresolved = binding.get("unresolved_capabilities")
    if not isinstance(unresolved, list):
        failures.append("UNRESOLVED_CAPABILITIES_INVALID")

    assurance = wp.get("pre_execution_assurance") or {}
    checks = set(assurance.get("checks") or [])
    missing_checks = sorted(MANDATORY_PREFLIGHT - checks)
    if missing_checks:
        failures.append("MANDATORY_PREFLIGHT_MISSING:" + ",".join(missing_checks))
    if assurance.get("material_work_allowed_only_if_all_pass") is not True:
        failures.append("MATERIAL_WORK_GUARD_INVALID")
    if assurance.get("failure_action") != FAIL:
        failures.append("PREFLIGHT_FAILURE_ACTION_INVALID")

    assertions = wp.get("assertions") or {}
    for field in ("acceptance", "failure", "blocking", "invalidation_conditions"):
        if not _list_of_strings(assertions.get(field), nonempty=True):
            failures.append("ASSERTIONS_MISSING:" + field)

    evidence = wp.get("evidence") or {}
    if not _list_of_strings(evidence.get("required_evidence"), nonempty=True):
        failures.append("REQUIRED_EVIDENCE_MISSING")
    if evidence.get("claim_ceiling") not in {"STRUCTURAL", "PROVENANCE", "SEMANTIC", "BEHAVIORAL"}:
        failures.append("CLAIM_CEILING_INVALID")
    for field in ("producer_receipt_required", "independent_judge_receipt_required", "readback_receipt_required"):
        if evidence.get(field) is not True:
            failures.append("EVIDENCE_REQUIREMENT_FALSE:" + field)

    frontier = wp.get("frontier") or {}
    for field in ("current_stage", "next_gate", "handoff_target", "handoff_contract"):
        if not isinstance(frontier.get(field), str) or not frontier[field]:
            failures.append("FRONTIER_FIELD_MISSING:" + field)
    if not isinstance(frontier.get("blockers"), list) or not isinstance(frontier.get("safe_parallel_work"), list):
        failures.append("FRONTIER_LIST_INVALID")

    closure = wp.get("closure") or {}
    if not _list_of_strings(closure.get("binary_conditions"), nonempty=True):
        failures.append("CLOSURE_CONDITIONS_MISSING")
    if closure.get("recompute_from_ledger") is not True:
        failures.append("CLOSURE_LEDGER_RECOMPUTE_REQUIRED")
    for field in ("main_merge_allowed", "production_allowed", "golden_promotion_allowed"):
        if closure.get(field) is not False:
            failures.append("BOOTSTRAP_SAFETY_CEILING_INVALID:" + field)

    material_candidate = frontier.get("next_gate") in {
        "MATERIAL_WORK", "BUILD", "IMPLEMENT", "WRITE", "PASS_TO_MATERIAL_WORK"
    }
    if material_candidate and unresolved:
        failures.append("UNRESOLVED_CAPABILITY_BLOCKS_MATERIAL_WORK")

    return {
        "contract": "LF_WORK_PACKAGE_BOOTSTRAP_V0_1",
        "result": FAIL if failures else PASS,
        "material_work_allowed": not failures,
        "failure_count": len(failures),
        "failures": failures,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_lf_work_package_bootstrap_v0_1.py <work-package.json>")
        return 2
    path = Path(sys.argv[1])
    wp = json.loads(path.read_text(encoding="utf-8"))
    result = validate(wp)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["result"] == PASS else 1


if __name__ == "__main__":
    raise SystemExit(main())
