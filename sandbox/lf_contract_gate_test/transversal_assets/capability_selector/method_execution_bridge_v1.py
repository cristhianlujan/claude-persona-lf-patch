"""Fail-closed selection-to-execution bridge for isolated Profile Evolution tests.

Synthetic executable fixtures are NOT governed production method implementations.
No production activation, authority writes, or arbitrary import/loading.
"""
from __future__ import annotations

import hashlib
import json
import time
from typing import Any, Callable

_ALLOWED_SCOPE = "TEST_NON_AUTHORITY"
_ALLOWED_STATE = "ACTIVE_FOR_CANDIDATE_EVALUATION"


def _sha(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":"), allow_nan=False).encode("utf-8")
    ).hexdigest()


def _blocked(*codes: str) -> dict[str, Any]:
    return {
        "schema": "PROFILE_METHOD_EXECUTION_BRIDGE_V1",
        "status": "BLOCKED",
        "blocking_codes": list(codes),
        "invocations": [],
        "actual_method_invocations": 0,
        "production_authorized": False,
        "profile_source_write_authorized": False,
        "cutover_eligible": False,
    }


def execute_method_selection(
    selection: dict[str, Any],
    registry: dict[str, Any],
    bindings: dict[str, dict[str, Any]],
    method_inputs: dict[str, dict[str, Any]],
    *,
    execution_id: str,
    evidence_refs: list[str],
    scope: str,
    permission_receipt: dict[str, Any],
    verify_permission: Callable[[dict[str, Any]], bool] | None,
    verify_selection: Callable[[dict[str, Any]], bool] | None,
    verify_result: Callable[[str, dict[str, Any], dict[str, Any]], bool] | None,
    result_verifier_id: str,
) -> dict[str, Any]:
    """Execute only *already selected* methods and emit auditable receipts.

    Permission verification MUST be supplied by the caller's independent
    permission resolver. Self-declared VERIFIED text does not grant access.
    This bridge deliberately allows only isolated non-authority execution.
    """
    if scope != _ALLOWED_SCOPE:
        return _blocked("RUNTIME_SCOPE_NOT_SUPPORTED")
    if not isinstance(registry, dict) or registry.get("execution_permission") is not True:
        return _blocked("REGISTRY_EXECUTION_PERMISSION_NOT_GRANTED")
    if not isinstance(selection, dict) or selection.get("schema") != "CAPABILITY_SELECTOR_COMPOSITION_V3":
        return _blocked("SELECTOR_RECEIPT_INVALID")
    if selection.get("execution_authorized") is not False:
        return _blocked("SELECTOR_MUST_NOT_SELF_AUTHORIZE")
    if selection.get("admission_required") is not True:
        return _blocked("SELECTOR_ADMISSION_INVARIANT_INVALID")
    if not isinstance(execution_id, str) or not execution_id.strip():
        return _blocked("EXECUTION_ID_REQUIRED")
    if not isinstance(evidence_refs, list) or not evidence_refs or not all(
        isinstance(x, str) and x for x in evidence_refs
    ):
        return _blocked("EVIDENCE_REQUIRED")
    if not isinstance(permission_receipt, dict) or not callable(verify_permission):
        return _blocked("INDEPENDENT_PERMISSION_VERIFIER_REQUIRED")
    if permission_receipt.get("scope") != scope or permission_receipt.get("execution_id") != execution_id:
        return _blocked("PERMISSION_SCOPE_OR_EXECUTION_MISMATCH")
    try:
        verified = verify_permission(permission_receipt) is True
    except Exception:
        verified = False
    if not verified:
        return _blocked("PERMISSION_NOT_INDEPENDENTLY_VERIFIED")
    if not callable(verify_selection):
        return _blocked("INDEPENDENT_SELECTION_VERIFIER_REQUIRED")
    try:
        if verify_selection(selection) is not True:
            return _blocked("SELECTION_NOT_INDEPENDENTLY_VERIFIED")
    except Exception:
        return _blocked("SELECTION_NOT_INDEPENDENTLY_VERIFIED")
    if not callable(verify_result) or not isinstance(result_verifier_id, str) or not result_verifier_id:
        return _blocked("INDEPENDENT_RESULT_VERIFIER_REQUIRED")

    selected = selection.get("selected_methods")
    if not isinstance(selected, list):
        return _blocked("SELECTED_METHODS_INVALID")
    if selection.get("fallback_state") in ("CONTRADICTORY", "CAPABILITY_FAILURE"):
        return _blocked("SELECTOR_UNRESOLVED")
    if not selected and selection.get("rejected_methods"):
        return _blocked("METHODS_REJECTED_NO_ELIGIBLE_EXECUTION")
    allowed = permission_receipt.get("allowed_method_ids")
    if not isinstance(allowed, list) or any(not isinstance(x, str) or not x for x in allowed):
        return _blocked("PERMISSION_METHOD_SCOPE_MISSING")
    if not {m.get("method_id") for m in selected if isinstance(m, dict)}.issubset(set(allowed)):
        return _blocked("PERMISSION_METHOD_NOT_ALLOWED")
    if not isinstance(bindings, dict) or not isinstance(method_inputs, dict):
        return _blocked("EXECUTION_BINDINGS_OR_INPUTS_INVALID")
    methods = registry.get("methods", [])
    if not isinstance(methods, list):
        return _blocked("METHOD_REGISTRY_INVALID")
    definitions = {m.get("method_id"): m for m in methods if isinstance(m, dict)}
    if len(definitions) != len(methods):
        return _blocked("METHOD_REGISTRY_DUPLICATE_OR_INVALID")

    # Preflight the entire set: no partial side-effects when a later binding
    # is missing or a method is experimental.
    seen: set[str] = set()
    for item in selected:
        if not isinstance(item, dict):
            return _blocked("SELECTED_METHOD_ITEM_INVALID")
        mid = item.get("method_id")
        if not isinstance(mid, str) or not mid or mid in seen:
            return _blocked("SELECTED_METHOD_DUPLICATE_OR_INVALID")
        seen.add(mid)
        registered = definitions.get(mid)
        if not registered:
            return _blocked("METHOD_NOT_REGISTERED")
        if registered.get("auto_select") is not True or registered.get("availability_state") != _ALLOWED_STATE:
            return _blocked("METHOD_NOT_EXECUTION_ELIGIBLE")
        if item.get("availability_state") != registered.get("availability_state"):
            return _blocked("METHOD_SELECTION_REGISTRY_MISMATCH")
        pre = item.get("precondition_receipt")
        if not isinstance(pre, dict) or pre.get("method_id") != mid or pre.get("status") != "PASS":
            return _blocked("PRECONDITION_NOT_VERIFIED")
        if not isinstance(item.get("cost_points"), (int, float)) or isinstance(item.get("cost_points"), bool) or item["cost_points"] < 0:
            return _blocked("METHOD_COST_INVALID")
        bound = bindings.get(mid)
        if not isinstance(bound, dict) or not callable(bound.get("handler")):
            return _blocked("METHOD_EXECUTOR_NOT_BOUND")
        if bound.get("scope") != scope:
            return _blocked("METHOD_BINDING_SCOPE_MISMATCH")
        if not all(isinstance(bound.get(k), str) and bound.get(k) for k in
                   ("executor_id", "execution_contract_ref", "source_revision")):
            return _blocked("METHOD_BINDING_IDENTITY_MISSING")
        if not isinstance(method_inputs.get(mid), dict):
            return _blocked("METHOD_INPUT_SCHEMA_MISSING")

    if not selected:
        return {
            **_blocked(),
            "status": "NO_METHOD_REQUIRED",
            "blocking_codes": [],
        }

    receipts: list[dict[str, Any]] = []
    for item in selected:
        mid = item["method_id"]
        bound = bindings[mid]
        payload = method_inputs[mid]
        started = time.perf_counter_ns()
        try:
            response = bound["handler"](payload)
            if not isinstance(response, dict) or response.get("verification_state") not in ("VERIFIED", "REJECTED"):
                raise ValueError("HANDLER_OUTPUT_CONTRACT_INVALID")
            success = response["verification_state"] == "VERIFIED" and verify_result(mid, payload, response) is True
            reason = "EXECUTED_AND_INDEPENDENTLY_VERIFIED" if success else "HANDLER_OR_VERIFIER_REJECTED"
            result_hash = _sha(response)
        except Exception as exc:
            success = False
            reason = "HANDLER_EXCEPTION_OR_OUTPUT_INVALID"
            result_hash = None
        wall_ms = round((time.perf_counter_ns() - started) / 1_000_000, 3)
        receipt = {
            "schema": "PROFILE_METHOD_INVOCATION_RECEIPT_V1",
            "execution_id": execution_id,
            "method_id": mid,
            "method_registry_revision": bound["source_revision"],
            "executor_id": bound["executor_id"],
            "execution_contract_ref": bound["execution_contract_ref"],
            "scope": scope,
            "evidence_refs": list(evidence_refs),
            "permission_receipt_sha256": _sha(permission_receipt),
            "selection_precondition_sha256": _sha(item["precondition_receipt"]),
            "input_sha256": _sha(payload),
            "result_sha256": result_hash,
            "result_verifier_id": result_verifier_id,
            "result_state": "EXECUTED_VERIFIED" if success else "EXECUTED_FAILED",
            "reason": reason,
            "observed_wall_ms": wall_ms,
            "authority_write": False,
            "production_authorized": False,
            "method_outcome_is_profile_improvement": False,
        }
        receipt["receipt_sha256"] = _sha(receipt)
        receipts.append(receipt)
        if not success:
            break

    completed = all(x["result_state"] == "EXECUTED_VERIFIED" for x in receipts)
    return {
        "schema": "PROFILE_METHOD_EXECUTION_BRIDGE_V1",
        "status": "EXECUTED_TEST_ONLY" if completed else "METHOD_FAILED",
        "blocking_codes": [] if completed else ["METHOD_EXECUTION_FAILED"],
        "invocations": receipts,
        "actual_method_invocations": len(receipts),
        "production_authorized": False,
        "profile_source_write_authorized": False,
        "cutover_eligible": False,
        "method_results_are_expert_benchmark": False,
    }
