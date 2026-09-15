#!/usr/bin/env python3
import json
import sys
from pathlib import Path

CONTRACT_VERSION = "AUTONOMOUS_DISCOVERY_REPAIR_CONTRACT_V1"
MATRIX_VERSION = "AUTONOMOUS_DISCOVERY_REPAIR_MATRIX_V1"
EXPECTED_DISCOVERY = [
    "DISCOVERY_PLAN",
    "INVENTORY_QUICK_SCAN",
    "CANDIDATE_SHORTLIST",
    "PRIORITIZE",
    "RECOMMEND_AND_SELECT",
    "SELECTED_CASE_DETAIL_READ",
    "CASE_FREEZE",
]
REQUIRED_TRACE_FIELDS = {
    "gate",
    "tool_name",
    "purpose",
    "source_object",
    "operation_kind",
    "query_or_request_digest",
    "exact_columns_or_fields",
    "filters",
    "limit_or_range",
    "rows_returned",
    "result_bytes_if_observed",
    "server_elapsed_ms_if_observed",
    "client_elapsed_ms_if_observed",
    "round_trip_index",
    "retry_count",
    "error_code_if_any",
    "cache_or_reuse",
    "read_scope",
    "output_digest",
}
REQUIRED_PROVENANCE = {
    "MOTOR_SELF",
    "EVALUATOR_FALLBACK",
    "TOOL_OBSERVED",
    "USER_OBSERVED",
}
REQUIRED_REPAIR_SEQUENCE = [
    "EKB_RECEIPT_CONFIRMED",
    "OWNER_ISOLATED",
    "TARGET_EVAL_BOUND",
    "CORRECT_UPDATE_OPERATION_ROUTED",
    "MINIMAL_CANDIDATE_FIX_IMPLEMENTED",
    "SOURCE_OR_HEAD_READBACK",
    "DETERMINISTIC_VALIDATION",
    "SAME_INPUT_GATE_REPLAY",
    "BEFORE_AFTER_VERIFIED",
    "CONTINUE",
]
REQUIRED_CASES = {
    "open_discovery_inventory_available",
    "open_discovery_inventory_unavailable",
    "evaluator_search_signature_leakage",
    "broad_select_star_without_justification",
    "unbounded_full_body_scan_before_shortlist",
    "correct_answer_with_overfetch",
    "existing_ekb_deficiency",
    "new_ekb_deficiency",
    "repair_before_ekb_readback",
    "next_gate_before_fix_replay",
    "evaluator_fallback_claimed_as_motor_self",
    "tool_error_schema_assumption",
    "cross_asset_fix_required",
}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, code, failures):
    if not condition:
        failures.append(code)


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    contract_path = root / "contracts/autonomous_discovery_repair_contract.json"
    matrix_path = root / "evals/autonomous_discovery_repair_matrix.json"
    failures = []

    require(contract_path.exists(), "MISSING_AUTONOMOUS_DISCOVERY_REPAIR_CONTRACT", failures)
    require(matrix_path.exists(), "MISSING_AUTONOMOUS_DISCOVERY_REPAIR_MATRIX", failures)
    if failures:
        print(json.dumps({"status": "FAIL", "blocking_codes": failures}, indent=2))
        return 1

    try:
        contract = load(contract_path)
        matrix = load(matrix_path)
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "blocking_codes": [f"JSON_PARSE_ERROR:{exc}"]}, indent=2))
        return 1

    require(contract.get("contract_version") == CONTRACT_VERSION, "BAD_CONTRACT_VERSION", failures)
    require(contract.get("status") == "CANDIDATE_READ_ONLY", "CONTRACT_MUST_REMAIN_CANDIDATE_READ_ONLY", failures)

    authority = contract.get("authority") or {}
    require(authority.get("router") == "ACT-0001", "ROUTER_AUTHORITY_MISMATCH", failures)
    require(authority.get("operational_source") == "SUPABASE", "OPERATIONAL_SOURCE_MUST_BE_SUPABASE", failures)
    require(authority.get("subject_asset") == "ACT-0046", "SUBJECT_ASSET_MISMATCH", failures)
    require(authority.get("automatic_impact") == "BLOCKED", "AUTOMATIC_IMPACT_MUST_BE_BLOCKED", failures)

    discovery = contract.get("no_case_behavior") or {}
    require(discovery.get("open_discovery_is_valid_input") is True, "OPEN_DISCOVERY_NOT_ENABLED", failures)
    require(discovery.get("ask_human_only_if_material_blocker") is True, "PREMATURE_HUMAN_DELEGATION_NOT_BLOCKED", failures)
    require(discovery.get("safe_reversible_selection_should_continue") is True, "SAFE_AUTONOMOUS_SELECTION_NOT_REQUIRED", failures)
    require(discovery.get("sequence") == EXPECTED_DISCOVERY, "DISCOVERY_SEQUENCE_MISMATCH", failures)

    access = contract.get("data_access") or {}
    for key in [
        "progressive_disclosure_required",
        "inventory_before_full_detail",
        "shortlist_before_deep_hydration",
        "select_star_without_justification_forbidden",
        "unbounded_collection_read_without_justification_forbidden",
        "full_body_scan_before_shortlist_is_red_flag",
        "repeated_identical_query_is_red_flag",
        "large_json_when_paths_suffice_is_red_flag",
        "metrics_must_not_be_invented_when_unobservable",
    ]:
        require(access.get(key) is True, f"DATA_ACCESS_GUARD_MISSING:{key}", failures)
    trace_fields = set(access.get("required_tool_trace_fields") or [])
    require(REQUIRED_TRACE_FIELDS.issubset(trace_fields), "TOOL_TRACE_FIELDS_INCOMPLETE", failures)
    require(set(access.get("read_scope_values") or []) == {"FOCAL", "BOUNDED", "BROAD", "SCHEMA_ONLY", "NON_DATA_TOOL"}, "READ_SCOPE_CATALOG_MISMATCH", failures)

    blind = contract.get("blind_evaluation") or {}
    for key in [
        "evaluator_must_not_construct_subject_search_signature",
        "search_signature_must_come_from_motor_output",
        "search_signature_must_be_frozen_before_retrieval",
        "oracle_terms_added_by_evaluator_invalidate_gate",
    ]:
        require(blind.get(key) is True, f"BLIND_EVAL_GUARD_MISSING:{key}", failures)

    enrich = contract.get("self_enrichment") or {}
    require(enrich.get("required") is True, "SELF_ENRICHMENT_NOT_REQUIRED", failures)
    require(enrich.get("writer_operation") == "ESCRITURA_BASE_CONOCIMIENTO_LF", "EKB_WRITER_OPERATION_MISMATCH", failures)
    require(enrich.get("writer") == "public.lf_write_pipeline_ekb_v1", "EKB_WRITER_MISMATCH", failures)
    require(enrich.get("no_repair_before_ekb_readback") is True, "REPAIR_ALLOWED_BEFORE_EKB_READBACK", failures)
    require(enrich.get("no_next_gate_before_ekb_readback") is True, "NEXT_GATE_ALLOWED_BEFORE_EKB_READBACK", failures)
    require(enrich.get("deduplicate_existing_causal_error") is True, "EKB_DEDUP_NOT_REQUIRED", failures)
    require(enrich.get("false_self_enrichment_claim_forbidden") is True, "FALSE_SELF_ENRICHMENT_NOT_FORBIDDEN", failures)
    require(REQUIRED_PROVENANCE.issubset(set(enrich.get("provenance_values") or [])), "SELF_ENRICHMENT_PROVENANCE_INCOMPLETE", failures)

    repair = contract.get("repair_loop") or {}
    require(repair.get("mode") == "FIX_BEFORE_NEXT_GATE", "REPAIR_MODE_MISMATCH", failures)
    require(repair.get("required") is True, "REPAIR_LOOP_NOT_REQUIRED", failures)
    require(repair.get("sequence") == REQUIRED_REPAIR_SEQUENCE, "REPAIR_SEQUENCE_MISMATCH", failures)
    require(repair.get("skill_update_operation") == "ACTUALIZACION_SKILL_LF", "SKILL_UPDATE_OPERATION_MISMATCH", failures)
    require(repair.get("gate_with_deficiency_cannot_complete_before_verified_fix") is True, "GATE_CAN_COMPLETE_WITH_OPEN_FIX", failures)
    require(repair.get("same_input_replay_required") is True, "SAME_INPUT_REPLAY_NOT_REQUIRED", failures)
    require(repair.get("merge_requires_separate_approval") is True, "MERGE_APPROVAL_GUARD_MISSING", failures)
    require(repair.get("production_promotion_requires_separate_approval") is True, "PRODUCTION_APPROVAL_GUARD_MISSING", failures)
    require(repair.get("cross_asset_write_requires_explicit_scope_approval") is True, "CROSS_ASSET_SCOPE_GUARD_MISSING", failures)

    finish = contract.get("finish_guard") or {}
    require(finish.get("all_gates_evaluated") is True, "FINISH_ALL_GATES_GUARD_MISSING", failures)
    require(finish.get("all_discovered_deficiencies_persisted") is True, "FINISH_EKB_PERSISTENCE_GUARD_MISSING", failures)
    require(finish.get("open_unimplemented_deficiencies_must_equal") == 0, "FINISH_OPEN_UNIMPLEMENTED_MUST_BE_ZERO", failures)
    require(finish.get("open_unverified_fixes_must_equal") == 0, "FINISH_OPEN_UNVERIFIED_MUST_BE_ZERO", failures)
    require(finish.get("all_in_scope_fixes_require_same_input_replay") is True, "FINISH_REPLAY_GUARD_MISSING", failures)
    require(finish.get("tool_efficiency_scoreboard_required") is True, "TOOL_EFFICIENCY_SCOREBOARD_NOT_REQUIRED", failures)
    require(finish.get("self_enrichment_scoreboard_required") is True, "SELF_ENRICHMENT_SCOREBOARD_NOT_REQUIRED", failures)

    require(matrix.get("matrix_version") == MATRIX_VERSION, "BAD_MATRIX_VERSION", failures)
    require(matrix.get("validation_scope") == "STRUCTURAL_CONTRACT_ONLY", "MATRIX_SCOPE_MUST_BE_STRUCTURAL", failures)
    require(matrix.get("behavioral_eval_status") == "NOT_EXECUTED", "MATRIX_FALSE_BEHAVIORAL_CLAIM", failures)
    cases = matrix.get("cases") or []
    ids = [c.get("id") for c in cases]
    require(len(ids) == len(set(ids)), "DUPLICATE_MATRIX_CASE_ID", failures)
    require(REQUIRED_CASES.issubset(set(ids)), "MATRIX_REQUIRED_CASES_MISSING", failures)
    for case in cases:
        cid = case.get("id") or "UNKNOWN"
        require(bool(case.get("expected")), f"MATRIX_CASE_EXPECTED_MISSING:{cid}", failures)
        require(isinstance(case.get("must_include"), list) and bool(case.get("must_include")), f"MATRIX_CASE_MUST_INCLUDE_MISSING:{cid}", failures)

    result = {
        "status": "STRUCTURAL_PASS" if not failures else "FAIL",
        "validation_scope": "STRUCTURAL_CONTRACT_ONLY",
        "behavioral_eval_status": "NOT_EXECUTED",
        "contract_version": contract.get("contract_version"),
        "matrix_version": matrix.get("matrix_version"),
        "matrix_case_count": len(cases),
        "blocking_codes": failures,
        "claim_ceiling": "This validator proves contract mechanics only; behavioral proof requires the live governed pilot and tool/output receipts."
    }
    print(json.dumps(result, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
