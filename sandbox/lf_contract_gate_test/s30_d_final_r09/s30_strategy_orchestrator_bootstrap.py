from __future__ import annotations

from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"

REQUIRED_STEP_ORDER = [
    "init_execution",
    "admission_and_portfolio_resolve",
    "strategy_set_resolve",
    "policy_and_currentness_resolve",
    "child_plan",
    "parent_control_reservation",
    "spawn_safe_children",
    "collect_child_receipts",
    "persist_checkpoint",
    "retry_or_continue_safe_children",
    "portfolio_independent_readback",
    "deterministic_and_semantic_judge",
    "close_guard",
    "report_output",
]


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_bootstrap_contract(contract: Mapping[str, Any]) -> dict:
    if contract.get("contract_version") != "S30_STRATEGY_ORCHESTRATOR_BOOTSTRAP_V1":
        return _block("BLOCK_ORCHESTRATOR_BOOTSTRAP_CONTRACT_VERSION")
    if contract.get("operation_code") != "ORQUESTACION_ESTRATEGIAS_LF":
        return _block("BLOCK_ORCHESTRATOR_OPERATION_CODE")
    if contract.get("child_operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_ORCHESTRATOR_CHILD_OPERATION")
    if contract.get("operation_role") != "PORTFOLIO_SUPERVISOR_NOT_BUSINESS_STATE_AUTHORITY":
        return _block("BLOCK_ORCHESTRATOR_ROLE")
    if contract.get("status") != "SOURCE_READY_NOT_REGISTERED" or contract.get("activation_status") != "NOT_REGISTERED_NOT_ACTIVE":
        return _block("BLOCK_ORCHESTRATOR_SOURCE_STATE")
    for key in (
        "runtime_activation", "scheduler_activation", "production_activation",
        "business_effect_dispatch_allowed", "supabase_registration_applied",
        "s26_mutation", "s31_mutation",
    ):
        if contract.get(key) is not False:
            return _block("BLOCK_ORCHESTRATOR_BOOTSTRAP_SIDE_EFFECT", field=key)
    steps = contract.get("steps")
    if not isinstance(steps, list):
        return _block("BLOCK_ORCHESTRATOR_STEP_SHAPE")
    observed = [x.get("step_id") for x in steps if isinstance(x, Mapping)]
    if observed != REQUIRED_STEP_ORDER:
        return _block("BLOCK_ORCHESTRATOR_STEP_SEQUENCE", observed=observed)
    orders = [x.get("order") for x in steps]
    if orders != sorted(orders) or len(set(orders)) != len(orders):
        return _block("BLOCK_ORCHESTRATOR_STEP_ORDER")
    inv = set(contract.get("mandatory_invariants") or [])
    required = {
        "ONE_CHILD_EXECUTION_PER_STRATEGY_TARGET",
        "CHILD_OPERATION_MUST_BE_EJECUCION_ESTRATEGIA_LF",
        "PARENT_MUST_NOT_PERFORM_MULTI_TARGET_BUSINESS_WRITES",
        "BLOCKED_CHILD_DOES_NOT_HIDE_UNRELATED_SAFE_CHILD",
        "CHILD_FAILURE_DISPOSITION_REQUIRED",
        "CHILD_RECEIPT_IDENTITY_AND_HASH_REQUIRED",
        "PARENT_CHECKPOINT_MONOTONIC",
        "INTERRUPTION_RESUMES_FROM_PERSISTED_PARENT_CHECKPOINT",
        "ZERO_EXECUTABLE_SAFE_SCOPES_BEFORE_CLOSE",
        "REPORT_PERSISTED_BEFORE_CLOSE",
        "NO_ORQUESTACION_PIPELINE_LF_IDENTITY_REUSE",
        "NO_CHAT_MEMORY_AS_STATE_AUTHORITY",
        "NO_SCHEDULER_AS_STATE_AUTHORITY",
        "NO_FINDING_QUOTA",
        "NO_HEURISTIC_AS_BLOCKING_GATE",
    }
    missing = sorted(required - inv)
    if missing:
        return _block("BLOCK_ORCHESTRATOR_INVARIANT_MISSING", missing=missing)
    if "ORQUESTACION_PIPELINE_LF_IDENTITY_REUSE" not in set(contract.get("forbidden") or []):
        return _block("BLOCK_ORCHESTRATOR_PIPELINE_REUSE_GUARD_MISSING")
    close = contract.get("close_policy") or {}
    close_required = set(close.get("required") or [])
    if "REPORT_PERSISTED" not in close_required or "ZERO_EXECUTABLE_SAFE_SCOPES_REMAINING" not in close_required:
        return _block("BLOCK_ORCHESTRATOR_CLOSE_POLICY")
    return {"status": PASS, "code": "PASS_ORCHESTRATOR_BOOTSTRAP_CONTRACT"}


def validate_registration_manifest(manifest: Mapping[str, Any]) -> dict:
    if manifest.get("contract_version") != "S30_STRATEGY_ORCHESTRATOR_REGISTRATION_MANIFEST_V1":
        return _block("BLOCK_ORCHESTRATOR_REGISTRATION_MANIFEST_VERSION")
    if manifest.get("operation_code") != "ORQUESTACION_ESTRATEGIAS_LF":
        return _block("BLOCK_ORCHESTRATOR_REGISTRATION_OPERATION")
    if manifest.get("status") != "SOURCE_ONLY_NOT_APPLIED":
        return _block("BLOCK_ORCHESTRATOR_REGISTRATION_SOURCE_STATE")
    actions = manifest.get("apply_actions") or {}
    for key in ("supabase_write", "ddl", "operation_registry_write", "runtime_activation", "scheduler_activation", "production_activation", "business_effect_dispatch"):
        if actions.get(key) is not False:
            return _block("BLOCK_ORCHESTRATOR_REGISTRATION_SIDE_EFFECT", field=key)
    expected = {
        "OPERATION_REGISTRY", "OPERATION_CONTRACTS", "OPERATION_STEPS",
        "OPERATION_STEP_CONTRACTS", "OPERATION_JUDGES",
        "OPERATION_STEP_JUDGE_BINDINGS", "OPERATION_POLICY_BINDINGS",
    }
    observed = {x.get("source_code") for x in (manifest.get("target_objects") or []) if isinstance(x, Mapping)}
    if observed != expected:
        return _block("BLOCK_ORCHESTRATOR_REGISTRATION_OBJECT_COVERAGE", missing=sorted(expected-observed), extra=sorted(observed-expected))
    policy = manifest.get("schema_binding_policy") or {}
    if policy.get("fresh_before_apply") is not True or policy.get("unknown_field_or_status_value") != "FAIL_CLOSED":
        return _block("BLOCK_ORCHESTRATOR_SCHEMA_POLICY")
    boundary = manifest.get("registration_boundary") or {}
    if boundary.get("owner_authorization_required") is not True:
        return _block("BLOCK_ORCHESTRATOR_OWNER_AUTH_REQUIRED")
    if boundary.get("runtime_activation_separate_authorization_required") is not True:
        return _block("BLOCK_ORCHESTRATOR_RUNTIME_AUTH_BOUNDARY")
    return {"status": PASS, "code": "PASS_ORCHESTRATOR_REGISTRATION_MANIFEST_SOURCE_ONLY"}


def simulate_canary(case: Mapping[str, Any]) -> str:
    mapping = {
        "NONE": "CANARY_PASS_MULTI_CHILD_NO_EFFECT",
        "ONE_BLOCKED_TWO_SAFE": "CONTINUE_TWO_SAFE_PERSIST_ONE_BLOCKED",
        "CHILD_EXECUTOR_NOT_CURRENT": "BLOCK_CHILD_EXECUTOR_NOT_CURRENT",
        "PARENT_BUSINESS_WRITE_ATTEMPT": "BLOCK_PARENT_BUSINESS_WRITE",
        "DUPLICATE_STRATEGY_TARGET": "BLOCK_DUPLICATE_CHILD_TARGET",
        "CHILD_RECEIPT_IDENTITY_MISMATCH": "BLOCK_CHILD_RECEIPT_BINDING",
        "INTERRUPTION_WITH_PARENT_CHECKPOINT": "RESUME_FROM_PARENT_CHECKPOINT",
        "STALE_PORTFOLIO_CURRENTNESS": "BLOCK_STALE_PORTFOLIO_CURRENTNESS",
        "CLOSE_WITH_NONTERMINAL_CHILD": "BLOCK_CLOSE_GUARD",
        "SCHEDULER_AS_STATE_AUTHORITY": "BLOCK_SCHEDULER_STATE_AUTHORITY",
        "PIPELINE_IDENTITY_REUSE": "BLOCK_PIPELINE_IDENTITY_REUSE",
        "ALL_TERMINAL_REPORT_PERSISTED": "CANARY_PASS_CLOSE_NO_EFFECT",
    }
    return mapping.get(case.get("fault"), "BLOCK_UNKNOWN_ORCHESTRATOR_CANARY_FAULT")


def validate_canary_blueprint(canary: Mapping[str, Any]) -> dict:
    if canary.get("contract_version") != "S30_STRATEGY_ORCHESTRATOR_CANARY_BLUEPRINT_V1":
        return _block("BLOCK_ORCHESTRATOR_CANARY_VERSION")
    if canary.get("operation_code") != "ORQUESTACION_ESTRATEGIAS_LF":
        return _block("BLOCK_ORCHESTRATOR_CANARY_OPERATION")
    if canary.get("child_operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_ORCHESTRATOR_CANARY_CHILD_OPERATION")
    cases = canary.get("cases") or []
    if canary.get("case_count") != len(cases) or len(cases) != 12:
        return _block("BLOCK_ORCHESTRATOR_CANARY_CASE_COUNT")
    mismatches = []
    for case in cases:
        actual = simulate_canary(case)
        if actual != case.get("expected"):
            mismatches.append({"case_id": case.get("case_id"), "expected": case.get("expected"), "actual": actual})
    if mismatches:
        return _block("BLOCK_ORCHESTRATOR_CANARY_EXPECTATION", mismatches=mismatches)
    sc = canary.get("success_criteria") or {}
    for key in (
        "preventable_first_hop_escape_count", "parent_business_write_count",
        "safe_child_skipped_count", "duplicate_child_execution_count",
        "lost_parent_checkpoint_count",
    ):
        if sc.get(key) != 0:
            return _block("BLOCK_ORCHESTRATOR_CANARY_HARD_TARGET", field=key)
    if any(sc.get(k) is not False for k in ("runtime_activation", "scheduler_activation", "business_effect_dispatch")):
        return _block("BLOCK_ORCHESTRATOR_CANARY_ACTIVATION")
    return {"status": PASS, "code": "PASS_ORCHESTRATOR_CANARY_BLUEPRINT", "case_count": len(cases)}


def registration_readiness(context: Mapping[str, Any]) -> dict:
    required_true = [
        "executor_registered_candidate_read_only",
        "executor_readiness_validated",
        "c05_dynamic_pass",
        "abc_d_closed_or_bound",
        "fresh_schema_readback",
        "operation_code_absent",
        "owner_registration_authorized",
    ]
    missing = [k for k in required_true if context.get(k) is not True]
    if missing:
        return _block("BLOCK_ORCHESTRATOR_REGISTRATION_PRECONDITION", missing=missing)
    return {
        "status": PASS,
        "code": "PASS_ORCHESTRATOR_REGISTRATION_AUTHORIZED_NOT_RUNTIME",
        "registration_allowed": True,
        "runtime_activation_allowed": False,
        "scheduler_activation_allowed": False,
        "business_effect_dispatch_allowed": False,
    }
