"""Six independent step judges for governed checkpoint closure (generic V1).

This module is pure/deterministic. It does NOT perform DB writes, grant access,
authenticate callers, or manufacture an authority receipt. The trusted runtime
MUST acquire `authority` by a fresh server-side readback after Router resolution,
not from a message, submitted form, mutable workflow input, or the case under test.
Fail closed when trusted evidence is absent. Do not use to activate an operation
unless the required real transactional + negative tests have passed.
"""
from __future__ import annotations

import re
from typing import Any, Mapping

OPERATION = "CIERRE_CHECKPOINT_INGENIERIA_LF"
TARGET_TYPE = "ENGINEERING_CHECKPOINT"
SHA = re.compile(r"^[a-f0-9]{64}$")
STEPS = (
    "init_execution",
    "router_authority",
    "provider_readback",
    "material_assertion",
    "checkpoint_transition",
    "independent_readback",
)


def _need(valid: bool, code: str) -> None:
    if not valid:
        raise ValueError("CP_CLOSE_" + code)


def _sha(value: Any) -> bool:
    return isinstance(value, str) and bool(SHA.fullmatch(value))


def _eq(evidence: Mapping[str, Any], field: str, expected: Any) -> bool:
    return field in evidence and evidence[field] == expected


def _is_nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _subset(actual: Mapping[str, Any], expected: Mapping[str, Any]) -> bool:
    return all(k in actual and actual[k] == v for k, v in expected.items())


def validate_step(
    step: str, evidence: Mapping[str, Any], authority: Mapping[str, Any]
) -> dict:
    """Validate one step against independently fetched canonical authority.

    These checks are evidence comparisons, not a grant to perform effects.
    """
    _need(step in STEPS, "UNKNOWN_STEP")
    _need(isinstance(evidence, Mapping), "EVIDENCE_OBJECT_REQUIRED")
    _need(isinstance(authority, Mapping), "AUTHORITY_OBJECT_REQUIRED")
    _need(authority.get("source_kind") == "CANONICAL_INDEPENDENT_READBACK",
          "UNTRUSTED_AUTHORITY")
    _need(authority.get("operation_code") == OPERATION, "WRONG_OPERATION")
    _need(authority.get("target_type") == TARGET_TYPE, "WRONG_TARGET_TYPE")
    _need(authority.get("target_count") == 1, "TARGET_NOT_SINGLE")
    _need(_is_nonempty(authority.get("target_code")), "TARGET_MISSING")
    _need(_is_nonempty(authority.get("execution_id")), "EXECUTION_MISSING")
    _need(authority.get("operation_lifecycle") == "OP_OPERATIONAL",
          "OPERATION_NOT_OPERATIONAL")
    _need(authority.get("operation_status") in ("SANDBOX_ACTIVE", "PRODUCCION_CONTROLADA"),
          "OPERATION_NOT_ACTIVE")
    _need(authority.get("route_write_allowed") is True, "ROUTE_NOT_WRITABLE")
    _need(authority.get("router") == "ACT-0001", "WRONG_ROUTER")

    def check(ok: bool, error: str) -> None:
        _need(ok, step.upper() + "_" + error)

    if step == "init_execution":
        check(_eq(evidence, "execution_id", authority["execution_id"]), "EXECUTION")
        check(_eq(evidence, "target_code", authority["target_code"]), "TARGET")
        check(authority.get("execution_state") == "IN_PROGRESS", "STATE")
        check(_is_nonempty(authority.get("idempotency_key")), "IDEMPOTENCY")
        check(_sha(authority.get("request_sha256")), "REQUEST_SHA")
        check(authority.get("runtime_authenticated") is True, "AUTHENTICATION")

    elif step == "router_authority":
        check(_eq(evidence, "router_receipt", authority.get("router_receipt"))
              and _is_nonempty(evidence.get("router_receipt")), "RECEIPT")
        check(authority.get("authority_applicable") is True
              and authority.get("authority_valid") is True, "VALIDATION")
        check(authority.get("route_action") == "CHECKPOINT_CLOSE", "ACTION")
        check(_sha(authority.get("operation_revision_sha256")), "REVISION_SHA")
        check(_eq(evidence, "operation_revision_sha256",
                  authority.get("operation_revision_sha256")), "REVISION_DRIFT")
        check(authority.get("route_status") == "READY_TO_EXECUTE", "ROUTE_STATUS")

    elif step == "provider_readback":
        check(_eq(evidence, "provider_ref", authority.get("provider_ref"))
              and _is_nonempty(evidence.get("provider_ref")), "PROVIDER")
        check(authority.get("provider_binding_state") == "ACTIVE", "BINDING")
        check(authority.get("provider_proof_status") == "PASS", "PROOF")
        check(authority.get("source_current") is True, "SOURCE")
        check(_eq(evidence, "source_current", True), "SOURCE_EVIDENCE")
        check(_sha(authority.get("assertion_contract_sha256")), "CONTRACT_SHA")
        expected = authority.get("pass_when")
        observed = authority.get("observed")
        check(isinstance(expected, Mapping) and len(expected) > 0,
              "PASS_WHEN_OBJECT")
        check(isinstance(observed, Mapping)
              and _subset(observed, expected), "OBSERVED_SEMANTICS")
        check(_eq(evidence, "proof_sha256", authority.get("proof_sha256"))
              and _sha(evidence.get("proof_sha256")), "PROOF_SHA")

    elif step == "material_assertion":
        check(_eq(evidence, "assertion_contract_sha256",
                  authority.get("assertion_contract_sha256"))
              and _sha(evidence.get("assertion_contract_sha256")), "CONTRACT")
        check(_eq(evidence, "assertion_receipt_sha256",
                  authority.get("assertion_receipt_sha256"))
              and _sha(evidence.get("assertion_receipt_sha256")), "RECEIPT")
        check(authority.get("assertion_passed") is True, "PASS_FALSE")
        check(authority.get("assertion_contract_current") is True, "STALE_CONTRACT")
        check(authority.get("receipt_is_canonical") is True, "NOT_CANONICAL")

    elif step == "checkpoint_transition":
        check(_eq(evidence, "from_status", authority.get("from_status"))
              and authority.get("from_status") in ("PENDING", "IN_PROGRESS"),
              "FROM_STATUS")
        check(_eq(evidence, "to_status", "DONE")
              and authority.get("checkpoint_status") == "DONE", "TO_STATUS")
        check(authority.get("material_done_guard_passed") is True, "DONE_GUARD")
        check(authority.get("authorized_checkpoint_count") == 1, "OTHER_CHECKPOINT")
        check(_eq(evidence, "effect_guard_receipt", authority.get("effect_guard_receipt"))
              and _is_nonempty(evidence.get("effect_guard_receipt")), "EFFECT_RECEIPT")
        check(authority.get("effect_state") == "SUCCEEDED", "EFFECT_NOT_SUCCEEDED")

    elif step == "independent_readback":
        check(_eq(evidence, "checkpoint_status", "DONE")
              and authority.get("checkpoint_status") == "DONE", "STATUS")
        check(_eq(evidence, "receipt_sha", authority.get("assertion_receipt_sha256"))
              and _sha(evidence.get("receipt_sha")), "ASSERTION_HASH")
        check(_eq(evidence, "next_checkpoint", authority.get("next_checkpoint"))
              and _is_nonempty(authority.get("next_checkpoint")), "NEXT")
        check(authority.get("effect_state") == "SUCCEEDED", "EFFECT")
        check(authority.get("rollback_test_passed") is True, "ROLLBACK_UNVERIFIED")
        check(authority.get("unintended_effect_count") == 0, "UNINTENDED_EFFECTS")
        check(authority.get("readback_source") == "CANONICAL_DB", "SOURCE")

    return {
        "valid": True,
        "code": "CP_CLOSE_" + step.upper() + "_VERIFIED",
        "server_assertions": ["checkpoint_close_" + step + "_verified"],
        "server_hard_fails": [],
    }
