from __future__ import annotations

from typing import Any, Mapping

from s30_strategy_executor_contract_binding_v1 import PASS, validate_contract_binding_v1

BLOCKED = "BLOCKED"
EXPECTED_OPERATION = "EJECUCION_ESTRATEGIA_LF"
EXPECTED_CODE = "LF_OPERATING_CONSTITUTION_POLICY_AUTONOMOUS_OPERATIONS_20260906"
EXPECTED_CANONICAL_NAME = "Estrategia 30 — Constitución operativa, sistema de políticas y operación autónoma continua LF"
EXPECTED_AUTHORITY = "public.lf_strategy_snapshots"
EXPECTED_IDENTITY_FIELD = "snapshot_code"
ALLOWED_STATUSES = {"CANDIDATO_READ_ONLY"}
ALLOWED_RUNTIME_STATES = {"PLAN_ONLY", "NO_HABILITADO"}
ALLOWED_IMPACT_POLICIES = {"BLOQUEADO", "NO_AUTOMATIC_PROMOTION"}
ZERO_EFFECT_FLAGS = (
    "business_effect_dispatch_allowed", "effect_guard_rows_allowed", "model_calls_allowed",
    "production_write_allowed", "strategy_snapshot_mutation_allowed", "scheduler_activation",
    "orchestrator_activation", "production_activation", "s26_mutation",
)


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_precanary_source_contract_v3(
    manifest: Mapping[str, Any],
    activation: Mapping[str, Any],
    family_matrix: Mapping[str, Any],
    live_canary: Mapping[str, Any],
    performance_policy: Mapping[str, Any],
    frozen_readback: Mapping[str, Any],
) -> dict:
    binding = validate_contract_binding_v1(
        manifest, activation, family_matrix, live_canary, performance_policy
    )
    if binding.get("status") != PASS:
        return _block("BLOCK_CURRENTNESS_V3_CONTRACT_BINDING", binding_code=binding.get("code"))

    if activation.get("contract_version") != "S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V3":
        return _block("BLOCK_CURRENTNESS_V3_ACTIVATION_VERSION")
    if activation.get("operation_code") != EXPECTED_OPERATION:
        return _block("BLOCK_CURRENTNESS_V3_OPERATION")
    if activation.get("status") != "SOURCE_CANDIDATE_AUTHORITY_CANONICAL_IDENTITY_PROVEN":
        return _block("BLOCK_CURRENTNESS_V3_SOURCE_STATUS")

    materialization = activation.get("materialization_policy") or {}
    for key in (
        "runtime_activation_authorization_required",
        "precanary_authority_currentness_required",
        "runtime_activation_blocked_until_fresh_authority_currentness",
    ):
        if materialization.get(key) is not True:
            return _block("BLOCK_CURRENTNESS_V3_MATERIALIZATION_POLICY", field=key)

    resolution = activation.get("strategy_resolution") or {}
    if resolution.get("authority") != EXPECTED_AUTHORITY or resolution.get("identity_field") != EXPECTED_IDENTITY_FIELD:
        return _block("BLOCK_CURRENTNESS_V3_RESOLUTION_AUTHORITY")
    if resolution.get("selector_kind") != "EXACT_SNAPSHOT_CODE" or resolution.get("canonical_canary_snapshot_code") != EXPECTED_CODE:
        return _block("BLOCK_CURRENTNESS_V3_RESOLUTION_SELECTOR")
    if resolution.get("resolved_snapshot_id") is not None:
        return _block("BLOCK_CURRENTNESS_V3_HARDCODED_ID_CONTRACT")
    if resolution.get("id_resolution") != "RESOLVE_FROM_EXACT_MATCH_AT_IMMEDIATE_PRE_RUNTIME":
        return _block("BLOCK_CURRENTNESS_V3_ID_RESOLUTION")
    if resolution.get("exactly_one_required") is not True:
        return _block("BLOCK_CURRENTNESS_V3_EXACT_MATCH_POLICY")
    if set(resolution.get("allowed_statuses") or []) != ALLOWED_STATUSES:
        return _block("BLOCK_CURRENTNESS_V3_ALLOWED_STATUS_POLICY")
    if set(resolution.get("allowed_runtime_states") or []) != ALLOWED_RUNTIME_STATES:
        return _block("BLOCK_CURRENTNESS_V3_ALLOWED_RUNTIME_STATE_POLICY")
    if set(resolution.get("allowed_impact_policies") or []) != ALLOWED_IMPACT_POLICIES:
        return _block("BLOCK_CURRENTNESS_V3_ALLOWED_IMPACT_POLICY")

    source_identity = resolution.get("source_identity_evidence_only") or {}
    if source_identity.get("observed_snapshot_id") != 35:
        return _block("BLOCK_CURRENTNESS_V3_SOURCE_OBSERVED_ID")
    if source_identity.get("observed_snapshot_id_is_execution_authority") is not False:
        return _block("BLOCK_CURRENTNESS_V3_HARDCODED_ID_AUTHORITY")
    if source_identity.get("canonical_name") != EXPECTED_CANONICAL_NAME:
        return _block("BLOCK_CURRENTNESS_V3_CANONICAL_NAME")

    gate = activation.get("precanary_currentness_gate") or {}
    if gate.get("required_before_runtime_authorization_request") is not True or gate.get("required_before_runtime_activation") is not True:
        return _block("BLOCK_CURRENTNESS_V3_GATE_POLICY")
    if gate.get("frozen_source_identity_evidence_satisfies_runtime_currentness") is not False:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_NOT_RUNTIME_CURRENT")
    if gate.get("readback_scope_required") != "IMMEDIATE_PRE_RUNTIME":
        return _block("BLOCK_CURRENTNESS_V3_READBACK_SCOPE_POLICY")

    if live_canary.get("contract_version") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V6":
        return _block("BLOCK_CURRENTNESS_V3_CANARY_VERSION")
    if live_canary.get("supersedes") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V5":
        return _block("BLOCK_CURRENTNESS_V3_CANARY_SUPERSEDES")
    if live_canary.get("canary_status") != "SOURCE_READY_AUTHORITY_IDENTITY_PROVEN_RUNTIME_AUTHORIZATION_PENDING":
        return _block("BLOCK_CURRENTNESS_V3_CANARY_SOURCE_STATUS")
    if live_canary.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY":
        return _block("BLOCK_CURRENTNESS_V3_RUNTIME_CLAIM")
    if live_canary.get("activation_authority") != "NONE":
        return _block("BLOCK_CURRENTNESS_V3_AUTHORITY_CLAIM")
    if any(live_canary.get(key) is not False for key in ZERO_EFFECT_FLAGS):
        return _block("BLOCK_CURRENTNESS_V3_ZERO_EFFECT_BOUNDARY")

    target = live_canary.get("target_strategy") or {}
    if target.get("selector_kind") != "EXACT_SNAPSHOT_CODE" or target.get("snapshot_code") != EXPECTED_CODE:
        return _block("BLOCK_CURRENTNESS_V3_CANARY_SELECTOR")
    if target.get("resolved_snapshot_id") is not None:
        return _block("BLOCK_CURRENTNESS_V3_CANARY_HARDCODED_ID")
    if target.get("id_resolution") != "RESOLVE_FROM_EXACT_MATCH_AT_IMMEDIATE_PRE_RUNTIME":
        return _block("BLOCK_CURRENTNESS_V3_CANARY_ID_RESOLUTION")

    if frozen_readback.get("readback_version") != "S30_STRATEGY_EXECUTOR_AUTHORITY_READBACK_V2":
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_VERSION")
    if frozen_readback.get("operation_code") != EXPECTED_OPERATION:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_OPERATION")
    if frozen_readback.get("authority") != EXPECTED_AUTHORITY or frozen_readback.get("identity_field") != EXPECTED_IDENTITY_FIELD:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_AUTHORITY")
    selector = frozen_readback.get("selector") or {}
    if selector.get("snapshot_code") != EXPECTED_CODE or selector.get("matching") != "EXACT":
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_SELECTOR")
    matches = frozen_readback.get("exact_matches") or []
    if frozen_readback.get("exact_match_count") != 1 or len(matches) != 1:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_EXPECTED_ONE")
    row = matches[0]
    if row.get("id") != 35 or row.get("snapshot_code") != EXPECTED_CODE or row.get("canonical_name") != EXPECTED_CANONICAL_NAME:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_IDENTITY_ROW")
    if row.get("status") not in ALLOWED_STATUSES or row.get("runtime_state") not in ALLOWED_RUNTIME_STATES or row.get("impact_policy") not in ALLOWED_IMPACT_POLICIES:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_SAFETY_ROW")
    if frozen_readback.get("runtime_activation_allowed") is not False:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_RUNTIME_CLAIM")
    if frozen_readback.get("readback_current_for_execution") is not False:
        return _block("BLOCK_CURRENTNESS_V3_FROZEN_READBACK_CURRENTNESS_CLAIM")

    return {
        "status": PASS,
        "code": "PASS_PRECANARY_BINDING_AND_CANONICAL_IDENTITY_SOURCE_ONLY",
        "binding_manifest": manifest.get("contract_version"),
        "runtime_execution_claimed": False,
        "runtime_activation_allowed": False,
        "canonical_snapshot_code": EXPECTED_CODE,
    }


def evaluate_authority_currentness_v3(
    activation: Mapping[str, Any],
    readback: Mapping[str, Any],
) -> dict:
    resolution = activation.get("strategy_resolution") or {}
    if resolution.get("canonical_canary_snapshot_code") != EXPECTED_CODE:
        return _block("BLOCK_AUTHORITY_SELECTOR_CONTRACT")
    if resolution.get("resolved_snapshot_id") is not None:
        return _block("BLOCK_AUTHORITY_HARDCODED_ID_CONTRACT")
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
