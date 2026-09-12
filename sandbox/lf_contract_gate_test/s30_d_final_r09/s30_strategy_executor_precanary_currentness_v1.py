from __future__ import annotations

from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"

EXPECTED_OPERATION = "EJECUCION_ESTRATEGIA_LF"
EXPECTED_CODE = "LF_S30_SHELL_ADVANCED_EXECUTION_20260903"
EXPECTED_AUTHORITY = "public.lf_strategy_snapshots"
EXPECTED_IDENTITY_FIELD = "snapshot_code"
ALLOWED_STATUSES = {"CANDIDATO_READ_ONLY"}
ALLOWED_RUNTIME_STATES = {"PLAN_ONLY", "NO_HABILITADO"}
ALLOWED_IMPACT_POLICIES = {"BLOQUEADO", "NO_AUTOMATIC_PROMOTION"}
ZERO_EFFECT_FLAGS = (
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


def validate_precanary_source_contract(
    activation_v2: Mapping[str, Any],
    live_canary_v4: Mapping[str, Any],
    frozen_readback: Mapping[str, Any],
) -> dict:
    if activation_v2.get("contract_version") != "S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V2":
        return _block("BLOCK_CURRENTNESS_ACTIVATION_VERSION")
    if activation_v2.get("supersedes") != "S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V1":
        return _block("BLOCK_CURRENTNESS_ACTIVATION_SUPERSEDES")
    if activation_v2.get("operation_code") != EXPECTED_OPERATION:
        return _block("BLOCK_CURRENTNESS_OPERATION")
    if activation_v2.get("status") != "SOURCE_CANDIDATE_AUTHORITY_NOT_MATERIALIZED":
        return _block("BLOCK_CURRENTNESS_SOURCE_STATUS")

    materialization = activation_v2.get("materialization_policy") or {}
    for key in (
        "runtime_activation_authorization_required",
        "precanary_authority_currentness_required",
        "runtime_activation_blocked_until_authority_current",
    ):
        if materialization.get(key) is not True:
            return _block("BLOCK_CURRENTNESS_MATERIALIZATION_POLICY", field=key)

    resolution = activation_v2.get("strategy_resolution") or {}
    expected = {
        "authority": EXPECTED_AUTHORITY,
        "identity_field": EXPECTED_IDENTITY_FIELD,
        "selector_kind": "EXACT_SNAPSHOT_CODE",
        "canonical_canary_snapshot_code": EXPECTED_CODE,
        "resolved_snapshot_id": None,
        "id_resolution": "RESOLVE_FROM_EXACT_MATCH_AT_IMMEDIATE_PRE_RUNTIME",
        "exactly_one_required": True,
        "currentness_status": "AUTHORITY_NOT_MATERIALIZED",
        "unknown_or_ambiguous": "BLOCK",
        "id_code_mismatch": "BLOCK",
        "stale_or_non_immediate_readback": "BLOCK",
        "hardcoded_snapshot_id_as_authority": "FORBIDDEN",
    }
    wrong = [key for key, value in expected.items() if resolution.get(key) != value]
    if wrong:
        return _block("BLOCK_CURRENTNESS_RESOLUTION_CONTRACT", fields=wrong)
    if set(resolution.get("allowed_statuses") or []) != ALLOWED_STATUSES:
        return _block("BLOCK_CURRENTNESS_ALLOWED_STATUS_POLICY")
    if set(resolution.get("allowed_runtime_states") or []) != ALLOWED_RUNTIME_STATES:
        return _block("BLOCK_CURRENTNESS_ALLOWED_RUNTIME_STATE_POLICY")
    if set(resolution.get("allowed_impact_policies") or []) != ALLOWED_IMPACT_POLICIES:
        return _block("BLOCK_CURRENTNESS_ALLOWED_IMPACT_POLICY")
    if resolution.get("authority_readback_ref") != "strategy_executor_authority_readback_20260912_v1.json":
        return _block("BLOCK_CURRENTNESS_READBACK_BINDING")

    gate = activation_v2.get("precanary_currentness_gate") or {}
    if gate.get("required_before_runtime_authorization_request") is not True:
        return _block("BLOCK_CURRENTNESS_BEFORE_AUTH_REQUEST")
    if gate.get("required_before_runtime_activation") is not True:
        return _block("BLOCK_CURRENTNESS_BEFORE_ACTIVATION")
    if gate.get("readback_scope_required") != "IMMEDIATE_PRE_RUNTIME":
        return _block("BLOCK_CURRENTNESS_READBACK_SCOPE_POLICY")
    if gate.get("exact_match_count_required") != 1:
        return _block("BLOCK_CURRENTNESS_EXACT_MATCH_POLICY")

    if live_canary_v4.get("contract_version") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V4":
        return _block("BLOCK_CURRENTNESS_CANARY_VERSION")
    if live_canary_v4.get("supersedes") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V3":
        return _block("BLOCK_CURRENTNESS_CANARY_SUPERSEDES")
    if live_canary_v4.get("operation_code") != EXPECTED_OPERATION:
        return _block("BLOCK_CURRENTNESS_CANARY_OPERATION")
    if live_canary_v4.get("activation_contract") != activation_v2.get("contract_version"):
        return _block("BLOCK_CURRENTNESS_CANARY_ACTIVATION_BINDING")
    if live_canary_v4.get("family_matrix_binding") != "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3":
        return _block("BLOCK_CURRENTNESS_FAMILY_MATRIX_BINDING")
    if live_canary_v4.get("performance_policy_binding") != "S30_STRATEGY_EXECUTOR_PERFORMANCE_POLICY_V1":
        return _block("BLOCK_CURRENTNESS_PERFORMANCE_BINDING")
    if live_canary_v4.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_CURRENTNESS_CANARY_MODE")
    if live_canary_v4.get("canary_status") != "BLOCKED_AUTHORITY_NOT_MATERIALIZED":
        return _block("BLOCK_CURRENTNESS_CANARY_SOURCE_STATUS")
    if live_canary_v4.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY":
        return _block("BLOCK_CURRENTNESS_RUNTIME_CLAIM")
    if live_canary_v4.get("activation_authority") != "NONE":
        return _block("BLOCK_CURRENTNESS_AUTHORITY_CLAIM")
    if any(live_canary_v4.get(key) is not False for key in ZERO_EFFECT_FLAGS):
        return _block("BLOCK_CURRENTNESS_ZERO_EFFECT_BOUNDARY")

    target = live_canary_v4.get("target_strategy") or {}
    if target.get("selector_kind") != "EXACT_SNAPSHOT_CODE" or target.get("snapshot_code") != EXPECTED_CODE:
        return _block("BLOCK_CURRENTNESS_CANARY_SELECTOR")
    if target.get("resolved_snapshot_id") is not None:
        return _block("BLOCK_CURRENTNESS_HARDCODED_ID")
    if target.get("resolution_status") != "AUTHORITY_NOT_MATERIALIZED":
        return _block("BLOCK_CURRENTNESS_CANARY_RESOLUTION_STATUS")
    if target.get("id_resolution") != "RESOLVE_FROM_EXACT_MATCH_AT_IMMEDIATE_PRE_RUNTIME":
        return _block("BLOCK_CURRENTNESS_CANARY_ID_RESOLUTION")
    if live_canary_v4.get("authority_readback_binding") != "strategy_executor_authority_readback_20260912_v1.json":
        return _block("BLOCK_CURRENTNESS_CANARY_READBACK_BINDING")

    canary_gate = live_canary_v4.get("precanary_currentness_gate") or {}
    if canary_gate.get("id") != "A00" or canary_gate.get("class") != "AUTHORITY_CURRENTNESS":
        return _block("BLOCK_CURRENTNESS_CANARY_GATE_IDENTITY")
    if canary_gate.get("required_before_runtime_authorization_request") is not True:
        return _block("BLOCK_CURRENTNESS_CANARY_GATE_AUTH_REQUEST")
    if canary_gate.get("required_before_runtime_activation") is not True:
        return _block("BLOCK_CURRENTNESS_CANARY_GATE_ACTIVATION")
    if canary_gate.get("fresh_readback_scope") != "IMMEDIATE_PRE_RUNTIME":
        return _block("BLOCK_CURRENTNESS_CANARY_GATE_SCOPE")

    if frozen_readback.get("readback_version") != "S30_STRATEGY_EXECUTOR_AUTHORITY_READBACK_V1":
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_VERSION")
    if frozen_readback.get("operation_code") != EXPECTED_OPERATION:
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_OPERATION")
    if frozen_readback.get("authority") != EXPECTED_AUTHORITY:
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_AUTHORITY")
    if frozen_readback.get("identity_field") != EXPECTED_IDENTITY_FIELD:
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_IDENTITY")
    selector = frozen_readback.get("selector") or {}
    if selector.get("snapshot_code") != EXPECTED_CODE or selector.get("matching") != "EXACT":
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_SELECTOR")
    if frozen_readback.get("exact_match_count") != 0 or frozen_readback.get("exact_matches") != []:
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_EXPECTED_ZERO")
    if frozen_readback.get("runtime_activation_allowed") is not False:
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_RUNTIME_CLAIM")
    if frozen_readback.get("readback_current_for_execution") is not False:
        return _block("BLOCK_CURRENTNESS_FROZEN_READBACK_CURRENTNESS_CLAIM")
    probe = frozen_readback.get("historical_hardcoded_id_probe") or []
    if len(probe) != 1 or probe[0].get("id") != 35 or probe[0].get("snapshot_code") == EXPECTED_CODE:
        return _block("BLOCK_CURRENTNESS_HISTORICAL_ID_EVIDENCE")

    return {
        "status": PASS,
        "code": "PASS_PRECANARY_CURRENTNESS_SOURCE_FAIL_CLOSED",
        "runtime_execution_claimed": False,
        "runtime_activation_allowed": False,
        "source_authority_state": "AUTHORITY_NOT_MATERIALIZED",
    }


def evaluate_authority_currentness(
    activation_v2: Mapping[str, Any],
    readback: Mapping[str, Any],
) -> dict:
    resolution = activation_v2.get("strategy_resolution") or {}
    if resolution.get("canonical_canary_snapshot_code") != EXPECTED_CODE:
        return _block("BLOCK_AUTHORITY_SELECTOR_CONTRACT")
    if readback.get("authority") != EXPECTED_AUTHORITY or readback.get("identity_field") != EXPECTED_IDENTITY_FIELD:
        return _block("BLOCK_AUTHORITY_READBACK_SOURCE")
    selector = readback.get("selector") or {}
    if selector.get("snapshot_code") != EXPECTED_CODE or selector.get("matching") != "EXACT":
        return _block("BLOCK_AUTHORITY_READBACK_SELECTOR")

    matches = readback.get("exact_matches")
    if not isinstance(matches, list):
        return _block("BLOCK_AUTHORITY_READBACK_SHAPE")
    count = readback.get("exact_match_count")
    if not isinstance(count, int) or count != len(matches):
        return _block("BLOCK_AUTHORITY_READBACK_COUNT")
    if count == 0:
        return _block("BLOCK_AUTHORITY_NOT_MATERIALIZED")
    if count != 1:
        return _block("BLOCK_AUTHORITY_AMBIGUOUS", exact_match_count=count)

    row = matches[0]
    if not isinstance(row, Mapping):
        return _block("BLOCK_AUTHORITY_READBACK_ROW")
    if row.get("snapshot_code") != EXPECTED_CODE:
        return _block("BLOCK_AUTHORITY_IDENTITY_MISMATCH")
    resolved_id = row.get("id")
    if not isinstance(resolved_id, int) or resolved_id <= 0:
        return _block("BLOCK_AUTHORITY_RESOLVED_ID")
    if row.get("status") not in ALLOWED_STATUSES:
        return _block("BLOCK_AUTHORITY_STATUS", observed=row.get("status"))
    if row.get("runtime_state") not in ALLOWED_RUNTIME_STATES:
        return _block("BLOCK_AUTHORITY_RUNTIME_STATE", observed=row.get("runtime_state"))
    if row.get("impact_policy") not in ALLOWED_IMPACT_POLICIES:
        return _block("BLOCK_AUTHORITY_IMPACT_POLICY", observed=row.get("impact_policy"))
    if readback.get("currentness_scope") != "IMMEDIATE_PRE_RUNTIME" or readback.get("readback_current_for_execution") is not True:
        return _block("BLOCK_AUTHORITY_CURRENTNESS_STALE")
    if not readback.get("observed_at"):
        return _block("BLOCK_AUTHORITY_OBSERVED_AT")

    return {
        "status": PASS,
        "code": "READY_FOR_RUNTIME_AUTHORIZATION_REQUEST",
        "snapshot_code": EXPECTED_CODE,
        "resolved_snapshot_id": resolved_id,
        "status_observed": row.get("status"),
        "runtime_state_observed": row.get("runtime_state"),
        "impact_policy_observed": row.get("impact_policy"),
        "observed_at": readback.get("observed_at"),
        "runtime_activation_authorized": False,
    }
