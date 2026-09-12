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


def validate_sandbox_activation_contract(activation: Mapping[str, Any], bootstrap: Mapping[str, Any]) -> dict:
    if activation.get("contract_version") != "S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V1":
        return _block("BLOCK_EXECUTOR_SANDBOX_ACTIVATION_VERSION")
    if activation.get("operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_EXECUTOR_SANDBOX_ACTIVATION_OPERATION")
    if activation.get("status") != "SOURCE_CANDIDATE_NOT_APPLIED":
        return _block("BLOCK_EXECUTOR_SANDBOX_ACTIVATION_SOURCE_STATE")
    if bootstrap.get("contract_version") != activation.get("source_bootstrap_contract"):
        return _block("BLOCK_EXECUTOR_SANDBOX_ACTIVATION_BOOTSTRAP_BINDING")
    if bootstrap.get("runtime_activation") is not False:
        return _block("BLOCK_EXECUTOR_BOOTSTRAP_MUST_REMAIN_INERT")
    policy = activation.get("materialization_policy") or {}
    if policy.get("fix_generator_not_live_artifact") is not True or policy.get("bootstrap_side_effect_flags_are_not_live_step_predicates") is not True:
        return _block("BLOCK_EXECUTOR_SANDBOX_GENERATOR_POLICY")
    if policy.get("target_registry_status") != "SANDBOX_ACTIVE" or policy.get("target_step_contract_status") != "ACTIVE_ENFORCEMENT":
        return _block("BLOCK_EXECUTOR_SANDBOX_TARGET_STATUS")
    router = activation.get("router_binding") or {}
    expected_router = {
        "asset_type": "STRATEGY", "action_code": "STRATEGY_EXECUTION",
        "operation_resolution": "STATIC", "requires_existing_target": False,
        "requires_missing_target": False, "write_allowed": False, "status": "ACTIVE",
    }
    if any(router.get(k) != v for k, v in expected_router.items()):
        return _block("BLOCK_EXECUTOR_SANDBOX_ROUTER_BINDING")
    if router.get("router_target_resolution") != "DEFER_TO_OPERATION_STRATEGY_RESOLVE" or router.get("target_binding_required_before_execution") is not True:
        return _block("BLOCK_EXECUTOR_SANDBOX_TARGET_BINDING")
    strategy = activation.get("strategy_resolution") or {}
    if strategy.get("authority") != "public.lf_strategy_snapshots" or strategy.get("identity_field") != "snapshot_code" or strategy.get("exactly_one_required") is not True:
        return _block("BLOCK_EXECUTOR_SANDBOX_STRATEGY_AUTHORITY")
    live = activation.get("live_step_projection") or {}
    required_pass = live.get("pass_condition_required") or {}
    if required_pass.get("runtime_mode") != "SANDBOX_CONTROLLED" or required_pass.get("runtime_activation_authorized") is not True:
        return _block("BLOCK_EXECUTOR_SANDBOX_LIVE_STEP_RUNTIME_MODE")
    forbidden = live.get("forbidden_copied_predicates") or []
    if {x.get("path") for x in forbidden if isinstance(x, Mapping)} != {"pass_condition.runtime_activation", "block_condition.runtime_activation_attempt"}:
        return _block("BLOCK_EXECUTOR_SANDBOX_FORBIDDEN_BOOTSTRAP_PREDICATES")
    boundary = activation.get("canary_boundary") or {}
    if boundary.get("mode") != "CONTROL_STATE_NO_EFFECT" or boundary.get("business_effect_dispatch_allowed") is not False or boundary.get("model_calls_allowed") is not False:
        return _block("BLOCK_EXECUTOR_SANDBOX_CANARY_BOUNDARY")
    if any(boundary.get(k) is not False for k in ("orchestrator_activation","scheduler_activation","production_activation","s26_mutation")):
        return _block("BLOCK_EXECUTOR_SANDBOX_FORBIDDEN_ACTIVATION")
    return {"status": PASS, "code": "PASS_EXECUTOR_SANDBOX_ACTIVATION_CONTRACT"}


def build_sandbox_materialization_plan(bootstrap: Mapping[str, Any], activation: Mapping[str, Any]) -> dict:
    valid = validate_sandbox_activation_contract(activation, bootstrap)
    if valid.get("status") != PASS:
        return valid
    live = activation["live_step_projection"]
    pass_required = dict(live["pass_condition_required"])
    block_required = dict(live["block_condition_required"])
    steps = []
    for step in bootstrap.get("steps") or []:
        if not isinstance(step, Mapping):
            return _block("BLOCK_EXECUTOR_SANDBOX_STEP_SHAPE")
        steps.append({
            "order": step.get("order"),
            "step_id": step.get("step_id"),
            "effect_class": step.get("effect_class"),
            "active": True,
            "status": "ACTIVE_ENFORCEMENT",
            "pass_condition": {"effect_class": step.get("effect_class"), "source_contract": bootstrap.get("contract_version"), **pass_required},
            "block_condition": {"source_contract_mismatch": True, "missing_required_evidence": True, **block_required},
        })
    return {
        "status": PASS,
        "code": "PASS_EXECUTOR_SANDBOX_MATERIALIZATION_PLAN",
        "registry_status": "SANDBOX_ACTIVE",
        "contract_status": "ACTIVE_ENFORCEMENT",
        "judge_status": "ACTIVE_ENFORCEMENT",
        "judge_binding_status": "ACTIVE_ENFORCEMENT",
        "policy_binding_status": "ACTIVE_UNCHANGED",
        "router_binding": dict(activation["router_binding"]),
        "steps": steps,
    }


def validate_sandbox_materialization_plan(plan: Mapping[str, Any], bootstrap: Mapping[str, Any]) -> dict:
    if plan.get("status") != PASS or plan.get("registry_status") != "SANDBOX_ACTIVE":
        return _block("BLOCK_EXECUTOR_SANDBOX_PLAN_STATE")
    steps = plan.get("steps") or []
    if len(steps) != len(bootstrap.get("steps") or []) or len(steps) != 15:
        return _block("BLOCK_EXECUTOR_SANDBOX_PLAN_STEP_COUNT")
    for step in steps:
        pc = step.get("pass_condition") or {}
        bc = step.get("block_condition") or {}
        if "runtime_activation" in pc or "runtime_activation_attempt" in bc:
            return _block("BLOCK_EXECUTOR_SANDBOX_BOOTSTRAP_PREDICATE_LEAK", step_id=step.get("step_id"))
        if pc.get("runtime_mode") != "SANDBOX_CONTROLLED" or pc.get("runtime_activation_authorized") is not True:
            return _block("BLOCK_EXECUTOR_SANDBOX_RUNTIME_AUTH_MISSING", step_id=step.get("step_id"))
        if bc.get("runtime_mode_not_sandbox_controlled") is not True or bc.get("target_strategy_binding_missing") is not True:
            return _block("BLOCK_EXECUTOR_SANDBOX_BLOCK_GUARD_MISSING", step_id=step.get("step_id"))
    return {"status": PASS, "code": "PASS_EXECUTOR_SANDBOX_MATERIALIZATION_PLAN_READBACK", "step_count": len(steps)}


def validate_live_canary_blueprint(canary: Mapping[str, Any], activation: Mapping[str, Any]) -> dict:
    if canary.get("contract_version") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V1":
        return _block("BLOCK_EXECUTOR_LIVE_CANARY_VERSION")
    if canary.get("activation_contract") != activation.get("contract_version"):
        return _block("BLOCK_EXECUTOR_LIVE_CANARY_ACTIVATION_BINDING")
    if canary.get("mode") != "CONTROL_STATE_NO_EFFECT" or canary.get("business_effect_dispatch_allowed") is not False or canary.get("model_calls_allowed") is not False:
        return _block("BLOCK_EXECUTOR_LIVE_CANARY_EFFECT_BOUNDARY")
    if any(canary.get(k) is not False for k in ("scheduler_activation","orchestrator_activation","production_activation","s26_mutation")):
        return _block("BLOCK_EXECUTOR_LIVE_CANARY_SCOPE")
    checks = canary.get("checks") or []
    required = {"ROUTER","ROUTER_NEGATIVE","STRATEGY_RESOLVE","IDEMPOTENCY","LEASE_CHECKPOINT","EFFECT_GUARD","STEP_EVIDENCE","CLOSE_GUARD","BOUNDARY"}
    observed = {x.get("class") for x in checks if isinstance(x, Mapping)}
    if observed != required:
        return _block("BLOCK_EXECUTOR_LIVE_CANARY_COVERAGE", missing=sorted(required-observed), extra=sorted(observed-required))
    if canary.get("finding_quota") is not None or canary.get("heuristic_as_gate") is not False:
        return _block("BLOCK_EXECUTOR_LIVE_CANARY_QUALITY_POLICY")
    return {"status": PASS, "code": "PASS_EXECUTOR_LIVE_CANARY_BLUEPRINT", "check_count": len(checks)}
