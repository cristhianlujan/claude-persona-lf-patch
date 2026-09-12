from __future__ import annotations

from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"

EXPECTED_OBJECTIVES = {f"F{i:02d}" for i in range(1, 15)}
REQUIRED_RUNTIME_NEGATIVE_CHECKS = {"L10", "L11", "L12", "L13", "L14"}
REQUIRED_STATIC_FAULTS = {
    "MULTI_STRATEGY_TARGET",
    "IDEMPOTENCY_HASH_CONFLICT",
    "LEASE_CONTENDED",
    "STALE_FENCE",
    "EFFECT_RESERVED_NO_RECEIPT",
    "QUALITY_NOMINAL_EVIDENCE",
    "NESTED_INTERNAL_HANDOFF_METADATA",
    "PRODUCER_SELF_READBACK",
    "ONE_BLOCKED_ONE_SAFE_SCOPE",
    "INTERRUPTION_WITH_CHECKPOINT",
    "CLOSE_WITH_EXECUTABLE_SCOPE_REMAINING",
}
REQUIRED_ZERO_EFFECT_FLAGS = (
    "business_effect_dispatch_allowed",
    "effect_guard_rows_allowed",
    "model_calls_allowed",
    "production_write_allowed",
    "strategy_snapshot_mutation_allowed",
    "scheduler_activation",
    "orchestrator_activation",
    "production_activation",
    "s26_mutation",
)


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_family_objective_matrix(
    matrix: Mapping[str, Any],
    activation: Mapping[str, Any],
    live_canary: Mapping[str, Any],
    dry_canary: Mapping[str, Any],
    bootstrap: Mapping[str, Any],
) -> dict:
    if matrix.get("matrix_version") != "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V2":
        return _block("BLOCK_FAMILY_MATRIX_VERSION")
    if matrix.get("operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_FAMILY_OPERATION_CODE")
    if matrix.get("activation_contract") != activation.get("contract_version"):
        return _block("BLOCK_FAMILY_ACTIVATION_BINDING")
    if matrix.get("runtime_canary_contract") != live_canary.get("contract_version"):
        return _block("BLOCK_FAMILY_CANARY_BINDING")
    if matrix.get("matrix_status") != "PRECANARY_ASSURANCE_READY_RUNTIME_EVIDENCE_PENDING":
        return _block("BLOCK_FAMILY_MATRIX_STATE")
    if any(matrix.get(k) is not False for k in ("runtime_execution_claimed", "production_activation_claimed", "authorization_claimed")):
        return _block("BLOCK_FAMILY_UNSUPPORTED_CLAIM")
    if matrix.get("claim_ceiling") != "SOURCE_AND_PRECANARY_ASSURANCE_ONLY":
        return _block("BLOCK_FAMILY_CLAIM_CEILING")

    objectives = matrix.get("objectives") or []
    ids = [o.get("id") for o in objectives if isinstance(o, Mapping)]
    if len(ids) != len(set(ids)) or set(ids) != EXPECTED_OBJECTIVES:
        return _block(
            "BLOCK_FAMILY_OBJECTIVE_COVERAGE",
            missing=sorted(EXPECTED_OBJECTIVES - set(ids)),
            extra=sorted(set(ids) - EXPECTED_OBJECTIVES),
        )

    allowed_runtime_states = {"REQUIRED_PENDING", "NOT_REQUIRED_AS_CANARY_STEP", "DEFERRED_BEYOND_ZERO_EFFECT_CANARY"}
    for objective in objectives:
        if not isinstance(objective, Mapping):
            return _block("BLOCK_FAMILY_OBJECTIVE_SHAPE")
        if not objective.get("family") or not objective.get("objective"):
            return _block("BLOCK_FAMILY_OBJECTIVE_SHAPE", objective_id=objective.get("id"))
        if not objective.get("positive_refs") or not objective.get("negative_refs") or not objective.get("evidence_refs"):
            return _block("BLOCK_FAMILY_OBJECTIVE_EVIDENCE", objective_id=objective.get("id"))
        runtime_status = objective.get("runtime_status")
        if runtime_status not in allowed_runtime_states:
            return _block("BLOCK_FAMILY_RUNTIME_STATE", objective_id=objective.get("id"))
        runtime_ids = objective.get("runtime_check_ids") or []
        if runtime_status == "REQUIRED_PENDING" and not runtime_ids:
            return _block("BLOCK_FAMILY_RUNTIME_MAPPING", objective_id=objective.get("id"))

    if activation.get("contract_version") != "S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V1":
        return _block("BLOCK_FAMILY_ACTIVATION_VERSION")
    if activation.get("status") != "SOURCE_CANDIDATE_NOT_APPLIED":
        return _block("BLOCK_FAMILY_ACTIVATION_SOURCE_STATE")
    strategy = activation.get("strategy_resolution") or {}
    if strategy.get("authority") != "public.lf_strategy_snapshots" or strategy.get("identity_field") != "snapshot_code":
        return _block("BLOCK_FAMILY_STRATEGY_AUTHORITY")
    if strategy.get("exactly_one_required") is not True or strategy.get("allowed_statuses") != ["CANDIDATO_READ_ONLY"] or strategy.get("unknown_or_ambiguous") != "BLOCK":
        return _block("BLOCK_FAMILY_STRATEGY_AUTHORITY")

    activation_boundary = activation.get("canary_boundary") or {}
    if activation_boundary.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_FAMILY_ZERO_EFFECT_BOUNDARY")
    if any(activation_boundary.get(k) is not False for k in REQUIRED_ZERO_EFFECT_FLAGS):
        return _block("BLOCK_FAMILY_ZERO_EFFECT_BOUNDARY")

    rollback = activation.get("rollback_policy") or {}
    if rollback.get("on_canary_failure") != "FAIL_CLOSED_DEMOTE_TO_CANDIDATO_READ_ONLY_AND_REMOVE_ROUTER_ACTION" or rollback.get("partial_activation_allowed") is not False:
        return _block("BLOCK_FAMILY_ROLLBACK_POLICY")

    steps = bootstrap.get("steps") or []
    step_ids = [s.get("step_id") for s in steps if isinstance(s, Mapping)]
    if len(step_ids) != 15 or len(step_ids) != len(set(step_ids)):
        return _block("BLOCK_FAMILY_STEP_COVERAGE")

    if live_canary.get("contract_version") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V2":
        return _block("BLOCK_FAMILY_LIVE_CANARY_VERSION")
    if live_canary.get("family_matrix_binding") != matrix.get("matrix_version"):
        return _block("BLOCK_FAMILY_LIVE_MATRIX_BINDING")
    if live_canary.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY" or live_canary.get("activation_authority") != "NONE":
        return _block("BLOCK_FAMILY_RUNTIME_CLAIM")
    if live_canary.get("mode") != "CONTROL_STATE_NO_EFFECT" or any(live_canary.get(k) is not False for k in REQUIRED_ZERO_EFFECT_FLAGS):
        return _block("BLOCK_FAMILY_LIVE_ZERO_EFFECT_BOUNDARY")

    target = live_canary.get("target_strategy") or {}
    if target.get("snapshot_id") != strategy.get("canonical_canary_snapshot_id") or target.get("snapshot_code") != strategy.get("canonical_canary_snapshot_code"):
        return _block("BLOCK_FAMILY_CANARY_TARGET_BINDING")

    checks = live_canary.get("checks") or []
    check_ids = [c.get("id") for c in checks if isinstance(c, Mapping)]
    if len(check_ids) != len(set(check_ids)):
        return _block("BLOCK_FAMILY_LIVE_CHECK_DUPLICATE")
    if not REQUIRED_RUNTIME_NEGATIVE_CHECKS.issubset(set(check_ids)):
        return _block("BLOCK_FAMILY_RUNTIME_NEGATIVE_COVERAGE", missing=sorted(REQUIRED_RUNTIME_NEGATIVE_CHECKS - set(check_ids)))
    if set(matrix.get("required_runtime_negative_checks") or []) != REQUIRED_RUNTIME_NEGATIVE_CHECKS:
        return _block("BLOCK_FAMILY_RUNTIME_NEGATIVE_POLICY")

    objective_ids = set(ids)
    for check in checks:
        if check.get("objective_id") not in objective_ids:
            return _block("BLOCK_FAMILY_LIVE_CHECK_OBJECTIVE_BINDING", check_id=check.get("id"))
        if not check.get("class") or not check.get("expected"):
            return _block("BLOCK_FAMILY_LIVE_CHECK_SHAPE", check_id=check.get("id"))

    known_checks = set(check_ids)
    for objective in objectives:
        unknown = sorted(set(objective.get("runtime_check_ids") or []) - known_checks)
        if unknown:
            return _block("BLOCK_FAMILY_RUNTIME_MAPPING", objective_id=objective.get("id"), unknown=unknown)

    dry_faults = {c.get("fault") for c in (dry_canary.get("cases") or []) if isinstance(c, Mapping)}
    matrix_faults = set(matrix.get("required_static_faults") or [])
    if matrix_faults != REQUIRED_STATIC_FAULTS:
        return _block("BLOCK_FAMILY_STATIC_FAULT_POLICY")
    if not REQUIRED_STATIC_FAULTS.issubset(dry_faults):
        return _block("BLOCK_FAMILY_STATIC_FAULT_COVERAGE", missing=sorted(REQUIRED_STATIC_FAULTS - dry_faults))

    return {
        "status": PASS,
        "code": "PASS_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V2",
        "objective_count": len(objectives),
        "live_check_count": len(checks),
        "runtime_negative_check_count": len(REQUIRED_RUNTIME_NEGATIVE_CHECKS),
        "runtime_execution_claimed": False,
    }
