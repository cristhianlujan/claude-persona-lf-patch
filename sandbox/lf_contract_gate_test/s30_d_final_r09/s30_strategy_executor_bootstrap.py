from __future__ import annotations

from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"

REQUIRED_STEP_ORDER = [
    "init_execution", "router", "strategy_resolve", "currentness_and_parent_read",
    "policy_and_quality_resolve", "reserve_idempotency_and_lease", "safe_work_discovery",
    "pre_write_execution_binding_gate", "execute_safe_macrobatch", "independent_readback",
    "deterministic_and_semantic_judge", "checkpoint_progress",
    "recovery_and_parallel_continue", "close_guard", "report_output",
]


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_bootstrap_contract(contract: Mapping[str, Any]) -> dict:
    if contract.get("contract_version") != "S30_STRATEGY_EXECUTOR_BOOTSTRAP_V1":
        return _block("BLOCK_EXECUTOR_BOOTSTRAP_CONTRACT_VERSION")
    if contract.get("operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_EXECUTOR_OPERATION_CODE")
    if contract.get("status") != "SOURCE_READY_NOT_REGISTERED" or contract.get("activation_status") != "NOT_REGISTERED_NOT_ACTIVE":
        return _block("BLOCK_EXECUTOR_SOURCE_STATE")
    if contract.get("target_cardinality") != "ONE_STRATEGY_PER_CHILD_EXECUTION":
        return _block("BLOCK_EXECUTOR_CARDINALITY")
    if any(contract.get(k) is not False for k in ("runtime_activation","scheduler_activation","production_activation","supabase_registration_applied","s26_mutation")):
        return _block("BLOCK_EXECUTOR_BOOTSTRAP_SIDE_EFFECT")
    steps = contract.get("steps")
    if not isinstance(steps, list) or [x.get("step_id") for x in steps if isinstance(x, Mapping)] != REQUIRED_STEP_ORDER:
        return _block("BLOCK_EXECUTOR_STEP_SEQUENCE")
    orders = [x.get("order") for x in steps]
    if orders != sorted(orders) or len(orders) != len(set(orders)):
        return _block("BLOCK_EXECUTOR_STEP_ORDER")
    inv = set(contract.get("mandatory_invariants") or [])
    required = {
        "ONE_STRATEGY_PER_EXECUTION", "REQUEST_HASH_BOUND_TO_IDEMPOTENCY_KEY",
        "LEASE_FENCE_REQUIRED_FOR_CHECKPOINT", "NO_EFFECT_BEFORE_EFFECT_GUARD_RESERVATION",
        "UNRESOLVED_EFFECT_REQUIRES_RECONCILIATION_NOT_REDISPATCH",
        "R16_QUALITY_BINDING_BEFORE_DOWNSTREAM_HANDOFF", "RECURSIVE_HANDOFF_ALLOWLIST",
        "INDEPENDENT_READBACK_NOT_PRODUCER_SELF_ATTESTATION",
        "BLOCKED_SCOPE_DOES_NOT_HIDE_UNRELATED_SAFE_SCOPE",
        "INTERRUPTION_RESUMES_FROM_PERSISTED_CHECKPOINT",
        "NO_CHAT_MEMORY_AS_STATE_AUTHORITY", "NO_SCHEDULER_AS_STATE_AUTHORITY",
        "NO_FINDING_QUOTA", "NO_HEURISTIC_AS_BLOCKING_GATE",
    }
    missing = sorted(required - inv)
    if missing:
        return _block("BLOCK_EXECUTOR_INVARIANT_MISSING", missing=missing)
    if contract.get("quality_binding") != "S30_EXECUTOR_QUALITY_BINDING_V2":
        return _block("BLOCK_EXECUTOR_R16_BINDING")
    if contract.get("reliability_binding") != "S30_C05_GENERIC_EXECUTION_RELIABILITY_V1":
        return _block("BLOCK_EXECUTOR_C05_BINDING")
    return {"status": PASS, "code": "PASS_EXECUTOR_BOOTSTRAP_CONTRACT"}


def validate_registration_manifest(manifest: Mapping[str, Any]) -> dict:
    if manifest.get("contract_version") != "S30_STRATEGY_EXECUTOR_REGISTRATION_MANIFEST_V1":
        return _block("BLOCK_EXECUTOR_REGISTRATION_MANIFEST_VERSION")
    if manifest.get("status") != "SOURCE_ONLY_NOT_APPLIED":
        return _block("BLOCK_EXECUTOR_REGISTRATION_ALREADY_APPLIED_OR_UNKNOWN")
    actions = manifest.get("apply_actions") or {}
    if any(actions.get(k) is not False for k in ("supabase_write","ddl","operation_registry_write","runtime_activation","scheduler_activation","production_activation")):
        return _block("BLOCK_EXECUTOR_REGISTRATION_SIDE_EFFECT")
    objects = manifest.get("target_objects") or []
    expected = {
        "OPERATION_REGISTRY", "OPERATION_CONTRACTS", "OPERATION_STEPS",
        "OPERATION_STEP_CONTRACTS", "OPERATION_JUDGES",
        "OPERATION_STEP_JUDGE_BINDINGS", "OPERATION_POLICY_BINDINGS",
    }
    observed = {x.get("source_code") for x in objects if isinstance(x, Mapping)}
    if observed != expected:
        return _block("BLOCK_EXECUTOR_REGISTRATION_OBJECT_COVERAGE", missing=sorted(expected-observed), extra=sorted(observed-expected))
    policy = manifest.get("schema_binding_policy") or {}
    if policy.get("fresh_before_apply") is not True or policy.get("unknown_field_or_status_value") != "FAIL_CLOSED":
        return _block("BLOCK_EXECUTOR_REGISTRATION_SCHEMA_POLICY")
    boundary = manifest.get("registration_boundary") or {}
    if boundary.get("owner_authorization_required") is not True or boundary.get("runtime_activation_separate_authorization_required") is not True:
        return _block("BLOCK_EXECUTOR_REGISTRATION_AUTH_BOUNDARY")
    return {"status": PASS, "code": "PASS_EXECUTOR_REGISTRATION_MANIFEST_SOURCE_ONLY"}


def registration_readiness(context: Mapping[str, Any]) -> dict:
    required_true = [
        "c05_dynamic_pass", "c05_source_parity_durable", "r16_durable",
        "typed_data_access_available", "fresh_schema_readback", "operation_code_absent",
    ]
    missing = [k for k in required_true if context.get(k) is not True]
    if missing:
        return _block("BLOCK_EXECUTOR_REGISTRATION_PRECONDITION", missing=missing)
    if context.get("owner_registration_authorized") is not True:
        return {"status": PASS, "code": "READY_FOR_REGISTRATION_AUTHORIZATION", "registration_allowed": False, "runtime_activation_allowed": False}
    return {"status": PASS, "code": "PASS_REGISTRATION_AUTHORIZED_NOT_RUNTIME", "registration_allowed": True, "runtime_activation_allowed": False}


def simulate_canary(case: Mapping[str, Any]) -> str:
    fault = case.get("fault")
    mapping = {
        "NONE":"CANARY_PASS_NO_EFFECT",
        "MULTI_STRATEGY_TARGET":"BLOCK_ONE_STRATEGY_PER_EXECUTION",
        "IDEMPOTENCY_HASH_CONFLICT":"BLOCK_IDEMPOTENCY_REQUEST_HASH_CONFLICT",
        "LEASE_CONTENDED":"BLOCK_LEASE_NOT_OWNED",
        "STALE_FENCE":"BLOCK_STALE_FENCE",
        "EFFECT_RESERVED_NO_RECEIPT":"RECONCILIATION_REQUIRED",
        "QUALITY_NOMINAL_EVIDENCE":"BLOCK_QUALITY_SUBSTANCE",
        "NESTED_INTERNAL_HANDOFF_METADATA":"BLOCK_HANDOFF_ALLOWLIST",
        "PRODUCER_SELF_READBACK":"BLOCK_READBACK_INDEPENDENCE",
        "ONE_BLOCKED_ONE_SAFE_SCOPE":"CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE",
        "INTERRUPTION_WITH_CHECKPOINT":"RESUME_FROM_PERSISTED_CHECKPOINT",
        "CLOSE_WITH_EXECUTABLE_SCOPE_REMAINING":"BLOCK_CLOSE_GUARD",
    }
    return mapping.get(fault, "BLOCK_UNKNOWN_CANARY_FAULT")
