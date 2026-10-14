"""Deterministic, per-step evidence comparisons for LF Edge deploy Operations.

Pure checks only; no network, no secret handling, no deployment, no DB writes.
The eventual authenticated Operations carrier MUST independently derive the
\`authority\` snapshot. Never accept the authority object from a workflow input.
"""
from __future__ import annotations

import re
from typing import Any, Mapping

OPERATION = "DEPLOY_SUPABASE_EDGE_FUNCTION_LF"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
STEPS = (
    "init_execution", "source_baseline", "r17_preflight",
    "human_authority", "effect_guard", "edge_deploy",
    "independent_readback", "close",
)

def _required(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)

def _eq(receipt: Mapping[str, Any], key: str, expected: Any) -> bool:
    return key in receipt and receipt[key] == expected

def validate_step(step: str, evidence: Mapping[str, Any], authority: Mapping[str, Any]) -> dict:
    """Compare evidence to *independently acquired* canonical authority.

    IMPORTANT: this function is not an authentication boundary. The runtime
    must obtain authority via its authenticated, scoped provider readbacks.
    """
    _required(step in STEPS, "EDGE_UNKNOWN_STEP")
    _required(isinstance(evidence, Mapping), "EDGE_EVIDENCE_SHAPE")
    _required(isinstance(authority, Mapping), "EDGE_AUTHORITY_SHAPE")
    _required(authority.get("operation_code") == OPERATION, "EDGE_WRONG_OPERATION")
    _required(authority.get("target_type") == "SUPABASE_EDGE_FUNCTION", "EDGE_WRONG_TARGET_TYPE")
    _required(authority.get("source_kind") == "CANONICAL_INDEPENDENT_READBACK", "EDGE_UNTRUSTED_AUTHORITY_SOURCE")
    _required(authority.get("target_count") == 1, "EDGE_TARGET_COUNT")

    target = authority.get("target")
    source_sha = authority.get("main_sha")
    _required(isinstance(target, str) and bool(re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", target)), "EDGE_INVALID_TARGET")
    _required(isinstance(source_sha, str) and bool(HEX40.fullmatch(source_sha)), "EDGE_INVALID_SOURCE_SHA")

    def check(ok: bool, code: str) -> None:
        _required(ok, "EDGE_" + step.upper() + "_" + code)

    if step == "init_execution":
        check(_eq(evidence, "execution_id", authority.get("execution_id")), "EXECUTION")
        check(_eq(evidence, "target_code", target), "TARGET")
        check(authority.get("operation_execution_state") == "IN_PROGRESS", "NOT_IN_PROGRESS")
    elif step == "source_baseline":
        check(_eq(evidence, "exact_main_sha", source_sha), "MAIN_SHA")
        check(_eq(evidence, "rollback_sha", authority.get("deployed_rollback_git_sha")), "ROLLBACK_SHA")
        check(_eq(evidence, "live_source_parity", True) and authority.get("rollback_bytes_equal_live") is True, "ROLLBACK_PARITY")
        check(authority.get("only_target_changed") is True, "OTHER_TARGET_DELTA")
        check(authority.get("jwt_mode_preserved") is True, "JWT_MODE")
    elif step == "r17_preflight":
        check(_eq(evidence, "r17_event_id", authority.get("r17_event_id")) and bool(evidence.get("r17_event_id")), "EVENT")
        check(_eq(evidence, "rollback_drill", "PASS") and authority.get("rollback_drill") == "PASS", "ROLLBACK_TEST")
        check(_eq(evidence, "idempotency", "PASS") and authority.get("idempotency") == "PASS", "IDEMPOTENCY")
        check(authority.get("r17_status") == "PASS", "STATUS")
        measured = evidence.get("timing")
        check(isinstance(measured, Mapping), "TIMING_SHAPE")
        for field in ("p50_ms", "p90_ms", "max_ms"):
            check(isinstance(measured.get(field), (int, float)) and not isinstance(measured[field], bool) and measured[field] >= 0, "TIMING_" + field.upper())
            check(measured[field] == (authority.get("timing") or {}).get(field), "TIMING_PARITY_" + field.upper())
        check(measured["p50_ms"] <= measured["p90_ms"] <= measured["max_ms"], "TIMING_ORDER")
        check(measured["max_ms"] <= authority.get("time_budget_ms", -1), "TIME_BUDGET")
    elif step == "human_authority":
        check(_eq(evidence, "signed_receipt", authority.get("human_receipt_id")) and bool(evidence.get("signed_receipt")), "SIGNED_RECEIPT")
        check(authority.get("human_role") == "SUPER_ADMIN" and authority.get("human_decision") == "APPROVE_DEPLOY", "ROLE_DECISION")
        check(_eq(evidence, "operation_current", True) and authority.get("operation_lifecycle") == "OP_OPERATIONAL", "OPERATION_NOT_CURRENT")
        check(_eq(evidence, "scope_exact", True) and authority.get("authorized_target") == target, "SCOPE")
        check(authority.get("route_write_allowed") is True and authority.get("runtime_effect_enabled") is True, "ROUTE_DISABLED")
    elif step == "effect_guard":
        check(_eq(evidence, "effect_scope", authority.get("effect_scope")), "SCOPE")
        req_sha = authority.get("request_sha256")
        check(isinstance(req_sha, str) and bool(HEX64.fullmatch(req_sha)) and _eq(evidence, "request_sha256", req_sha), "REQUEST_SHA")
        check(_eq(evidence, "reservation_receipt", authority.get("reservation_receipt")) and bool(evidence.get("reservation_receipt")), "RESERVATION")
        check(authority.get("effect_state") == "RESERVED" and authority.get("dispatch_permitted") is True, "EFFECT_NOT_RESERVED")
    elif step == "edge_deploy":
        check(_eq(evidence, "deploy_execution_id", authority.get("deploy_execution_id")), "DEPLOY_ID")
        check(_eq(evidence, "provider_receipt", authority.get("provider_receipt")) and bool(evidence.get("provider_receipt")), "PROVIDER_RECEIPT")
        check(_eq(evidence, "source_sha", source_sha), "DEPLOY_SHA")
        check(authority.get("provider_target") == target and authority.get("provider_deployed") is True, "PROVIDER_TARGET")
    elif step == "independent_readback":
        check(_eq(evidence, "deployed_source", source_sha) and authority.get("deployed_source_sha") == source_sha, "SOURCE_MISMATCH")
        check(_eq(evidence, "oidc_probe", authority.get("oidc_probe_receipt")) and bool(evidence.get("oidc_probe")), "OIDC_PROBE")
        check(_eq(evidence, "rollback_state", authority.get("rollback_state")), "ROLLBACK_STATE")
        check(authority.get("oidc_action_scope_mismatch") is False, "OIDC_SCOPE_MISMATCH")
        check(authority.get("deployed_verify_jwt") == authority.get("prior_verify_jwt"), "JWT_MODE_DRIFT")
        check(authority.get("cp2_jobs_started") == 0, "UNEXPECTED_CP2_RUNS")
    elif step == "close":
        check(_eq(evidence, "effect_guard_receipt", authority.get("effect_guard_receipt")) and bool(evidence.get("effect_guard_receipt")), "EFFECT_RECEIPT")
        check(_eq(evidence, "parity", "PASS") and authority.get("independent_parity") == "PASS", "SOURCE_PARITY")
        check(_eq(evidence, "open_blockers", []) and authority.get("open_blockers") == [], "BLOCKERS")
        check(authority.get("effect_state") == "SUCCEEDED" and authority.get("release_promoted") is False, "EFFECT_OR_PROMOTION")
        check(authority.get("cp2_jobs_started") == 0, "CP2_RUNS")

    return {
        "valid": True,
        "code": "EDGE_" + step.upper() + "_VERIFIED",
        "server_assertions": ["edge_" + step + "_verified"],
        "server_hard_fails": [],
    }
