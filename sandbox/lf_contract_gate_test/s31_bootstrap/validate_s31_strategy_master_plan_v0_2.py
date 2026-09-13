#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parent
PLAN_PATH = ROOT / "s31_strategy_master_plan_v0_2.json"
HEX40 = re.compile(r"^[0-9a-f]{40}$")

REQUIRED_SEQUENCE = [
    "ADMISSION_WORK_PACKAGE",
    "FRESH_EKB_AUTHORITY_CURRENTNESS",
    "SOURCE_SCHEMA_CONTRACT_RESOLUTION",
    "MATERIAL_CHANGE",
    "DETERMINISTIC_VALIDATION",
    "ADVERSARIAL_BYPASS_AUDIT",
    "REPAIR_AND_REGRESSION_IF_NEEDED",
    "GLOBAL_SAFE_WORK_RESCAN",
    "SCOPE_SPECIFIC_FREEZE",
    "INDEPENDENT_SEMANTIC_REVIEW",
    "CROSS_LANE_RECONCILIATION",
    "INTEGRATION_REPLAY",
    "EXPLICIT_PROMOTION_DECISION",
]
REQUIRED_DIMENSIONS = {
    "ARTIFACT_MATURITY",
    "EVIDENCE_LEVEL",
    "RUNTIME_ACTIVATION",
    "PROMOTION_AUTHORITY",
}
REQUIRED_H_PREREQS = {
    "S31_A_TO_G_INDEPENDENT_SEMANTIC_REVIEW_RESOLVED",
    "CROSS_LANE_RECONCILIATION_PASS",
    "INTERNAL_PORT_CONTRACTS_STABLE",
}


def _block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": "BLOCKED", "code": code, **extra}


def _require_true(obj: Mapping[str, Any], keys: list[str], code: str) -> dict[str, Any] | None:
    missing = [k for k in keys if obj.get(k) is not True]
    if missing:
        return _block(code, missing=missing)
    return None


def validate_plan(plan: Mapping[str, Any]) -> dict[str, Any]:
    if plan.get("plan_version") != "S31_STRATEGY_MASTER_PLAN_V0_2":
        return _block("BLOCK_PLAN_VERSION")
    if plan.get("strategy_id") != "S31":
        return _block("BLOCK_STRATEGY_ID")
    if plan.get("historical_bootstrap_preserved") is not True:
        return _block("BLOCK_HISTORY_REWRITE")
    if not HEX40.match(str(plan.get("base_main_sha", ""))):
        return _block("BLOCK_BASE_MAIN_SHA")

    if plan.get("execution_sequence") != REQUIRED_SEQUENCE:
        return _block("BLOCK_EXECUTION_SEQUENCE_DRIFT")

    ownership = plan.get("ownership") or {}
    x = _require_true(
        ownership,
        [
            "s31_generalizes",
            "owner_internals_remain_owned_by_source_strategy",
            "direct_mutation_of_s30_s26_learning_story_creator_forbidden",
            "big_bang_migration_forbidden",
        ],
        "BLOCK_OWNERSHIP_BOUNDARY_WEAKENED",
    )
    if x:
        return x

    close = plan.get("close_policy") or {}
    x = _require_true(
        close,
        [
            "safe_parallel_work_nonempty_forbids_close",
            "remaining_safe_scope_count_nonzero_forbids_close",
            "next_safe_batch_present_forbids_close",
            "safe_work_list_count_batch_must_be_coherent",
            "frontier_close_guard_must_be_coherent",
            "global_remaining_work_discovery_required_before_zero_safe_work",
            "blocked_scope_does_not_hide_unrelated_safe_scope",
            "discovered_safe_work_is_execution_obligation",
        ],
        "BLOCK_ANTI_CLOSE_WEAKENED",
    )
    if x:
        return x
    if close.get("unresolved_blocker_with_no_safe_work_disposition") != "BLOCKED_CAUSAL_NO_SAFE_WORK":
        return _block("BLOCK_UNRESOLVED_BLOCKER_CLOSE_BYPASS")

    defect = plan.get("defect_response") or {}
    x = _require_true(
        defect,
        [
            "reproduce_earliest_sufficient_cause",
            "repair_earliest_deterministic_owner",
            "regression_required",
            "transversal_defect_requires_plan_or_contract_evolution",
            "identical_retry_without_new_evidence_forbidden",
        ],
        "BLOCK_DEFECT_LEARNING_CHAIN_WEAKENED",
    )
    if x:
        return x
    if defect.get("workaround_without_causal_repair_is_closure") is not False:
        return _block("BLOCK_WORKAROUND_AS_CLOSURE")

    dims = plan.get("evidence_lifecycle_dimensions")
    if not isinstance(dims, list) or set(dims) != REQUIRED_DIMENSIONS or len(dims) != 4:
        return _block("BLOCK_LIFECYCLE_DIMENSIONS_COLLAPSED")

    evidence = plan.get("evidence_rules") or {}
    if evidence.get("canonical_lifecycle_vocabulary_status") != "UNRESOLVED":
        return _block("BLOCK_LIFECYCLE_VOCABULARY_OVERCLAIM")
    x = _require_true(
        evidence,
        [
            "self_certification_forbidden",
            "structural_cannot_promote_semantic_or_behavioral",
            "provenance_does_not_imply_semantic_correctness",
            "deterministic_pass_does_not_imply_independent_semantic_pass",
            "semantic_pass_does_not_imply_live_behavioral_pass",
            "ci_green_does_not_authorize_promotion",
        ],
        "BLOCK_EVIDENCE_CEILING_WEAKENED",
    )
    if x:
        return x

    review = plan.get("review_policy") or {}
    if review.get("canonical_receiver") != "QUALITY_PACK" or review.get("execution_mode") != "INDEPENDENT_CHAT_CONTEXT":
        return _block("BLOCK_CANONICAL_REVIEW_BOUNDARY")
    x = _require_true(
        review,
        [
            "parallel_custom_receipt_contract_forbidden",
            "scope_specific_freeze",
            "minimal_causally_affected_refreeze",
            "producer_target_verdict_forbidden",
        ],
        "BLOCK_REVIEW_POLICY_WEAKENED",
    )
    if x:
        return x
    snapshots = review.get("current_snapshots") or {}
    if set(snapshots) != {"ABC", "DG"} or any(not HEX40.match(str(v)) for v in snapshots.values()):
        return _block("BLOCK_REVIEW_SNAPSHOT_INVALID")

    lanes = plan.get("lanes") or {}
    if set(lanes) != {f"S31-{c}" for c in "ABCDEFGH"}:
        return _block("BLOCK_LANE_SET_DRIFT")
    if lanes["S31-H"].get("state") != "PLAN_ONLY_DEFERRED" or lanes["S31-H"].get("next_gate") != "AFTER_A_G_SEMANTIC_RECONCILIATION":
        return _block("BLOCK_S31_H_PREMATURE_ADVANCE")

    h = plan.get("s31_h_policy") or {}
    if set(h.get("prerequisites") or []) != REQUIRED_H_PREREQS:
        return _block("BLOCK_S31_H_PREREQUISITES")
    if h.get("framework_is_authority") is not False or h.get("framework_is_source_of_truth") is not False:
        return _block("BLOCK_FRAMEWORK_AUTHORITY_LEAK")
    if h.get("framework_must_be_replaceable_behind_port") is not True:
        return _block("BLOCK_FRAMEWORK_LOCK_IN")
    if h.get("install_or_poc_execution_currently_authorized") is not False:
        return _block("BLOCK_EXTERNAL_POC_PREMATURE_AUTHORIZATION")

    promotion = plan.get("promotion_authority") or {}
    if any(promotion.get(k) is not False for k in [
        "merge_main_authorized",
        "golden_authorized",
        "runtime_activation_authorized",
        "production_authorized",
    ]):
        return _block("BLOCK_PROMOTION_AUTHORITY_OVERCLAIM")

    completion = plan.get("completion_definition") or {}
    x = _require_true(
        completion,
        [
            "deterministic_and_adversarial_pass_required",
            "independent_semantic_pass_required",
            "cross_lane_reconciliation_required",
            "currentness_and_reconstructibility_required",
            "no_applicable_high_critical_blocker_required",
            "global_safe_work_exhaustion_required",
            "terminal_disposition_per_target_scope_required",
            "s31_h_pocs_are_separate_post_core_gate",
        ],
        "BLOCK_COMPLETION_DEFINITION_WEAKENED",
    )
    if x:
        return x

    return {"status": "PASS", "code": "PASS_S31_STRATEGY_MASTER_PLAN_V0_2"}


def main() -> int:
    import sys
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else PLAN_PATH
    plan = json.loads(path.read_text(encoding="utf-8"))
    result = validate_plan(plan)
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
