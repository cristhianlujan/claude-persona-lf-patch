#!/usr/bin/env python3
"""Deterministic execution contract for LF governed profile runs."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

SCHEMA = "LF_PROFILE_EXECUTION_CONTRACT_V1"
CONTROL_RECEIPT_TYPE = "PROFILE_EXECUTION_CONTROL_RECEIPT_V1"
EXECUTOR_MODES = {"GPT_NATIVE", "CLAUDE_NATIVE", "REMOTE_API"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class ExecutionContractError(ValueError):
    pass


def canonical_json_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_sha256(value: Any) -> bool:
    return isinstance(value, str) and bool(SHA256_RE.fullmatch(value))


def _validate_unique_string_list(errors: list[str], name: str, value: Any, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list):
        errors.append(f"{name.upper()}_NOT_ARRAY")
        return []
    if not allow_empty and not value:
        errors.append(f"{name.upper()}_EMPTY")
        return []
    if any(not _nonempty_string(item) for item in value):
        errors.append(f"{name.upper()}_ITEM_INVALID")
        return []
    if len(value) != len(set(value)):
        errors.append(f"{name.upper()}_DUPLICATE")
    return list(value)


def _validate_cards(errors: list[str], value: Any) -> None:
    if not isinstance(value, list) or not value:
        errors.append("CARD_REFS_AND_HASHES_INVALID")
        return
    seen: set[str] = set()
    for index, item in enumerate(value):
        prefix = f"CARD_{index}"
        if not isinstance(item, dict):
            errors.append(f"{prefix}_NOT_OBJECT")
            continue
        ref = item.get("ref")
        sha = item.get("sha256")
        if not _nonempty_string(ref):
            errors.append(f"{prefix}_REF_INVALID")
        if not _is_sha256(sha):
            errors.append(f"{prefix}_SHA256_INVALID")
        if _nonempty_string(ref):
            if ref in seen:
                errors.append("CARD_REF_DUPLICATE")
            seen.add(ref)


def validate_execution_contract(
    contract: Any,
    *,
    expected_profile_code: str | None = None,
    expected_executor_mode: str | None = None,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(contract, dict):
        return ["EXECUTION_CONTRACT_NOT_OBJECT"]

    required_strings = (
        "schema", "run_id", "profile_code", "profile_version", "objective", "current_gate",
        "input_governance_ref", "adapter_ref", "context_fingerprint", "executor_mode", "contract_sha256",
    )
    for key in required_strings:
        if not _nonempty_string(contract.get(key)):
            errors.append(f"MISSING_OR_EMPTY_{key.upper()}")

    if contract.get("schema") != SCHEMA:
        errors.append("EXECUTION_CONTRACT_SCHEMA_INVALID")
    if contract.get("executor_mode") not in EXECUTOR_MODES:
        errors.append("EXECUTOR_MODE_INVALID")
    if expected_profile_code is not None and contract.get("profile_code") != expected_profile_code:
        errors.append("PROFILE_CODE_MISMATCH")
    if expected_executor_mode is not None and contract.get("executor_mode") != expected_executor_mode:
        errors.append("EXECUTOR_MODE_MISMATCH")
    if _nonempty_string(contract.get("context_fingerprint")) and not _is_sha256(contract.get("context_fingerprint")):
        errors.append("CONTEXT_FINGERPRINT_INVALID")

    authorized_scope = _validate_unique_string_list(errors, "authorized_scope", contract.get("authorized_scope"))
    allowed_actions = _validate_unique_string_list(errors, "allowed_actions", contract.get("allowed_actions"))
    forbidden_actions = _validate_unique_string_list(errors, "forbidden_actions", contract.get("forbidden_actions"))
    _validate_unique_string_list(errors, "required_checks", contract.get("required_checks"))
    _validate_unique_string_list(errors, "required_evidence", contract.get("required_evidence"))
    _validate_unique_string_list(errors, "closure_conditions", contract.get("closure_conditions"))
    _validate_unique_string_list(errors, "tool_permissions", contract.get("tool_permissions"))

    if authorized_scope and any(item.startswith("/") for item in authorized_scope):
        errors.append("AUTHORIZED_SCOPE_ABSOLUTE_PATH_FORBIDDEN")
    overlap = sorted(set(allowed_actions) & set(forbidden_actions))
    if overlap:
        errors.append("ACTION_POLICY_OVERLAP:" + ",".join(overlap))

    _validate_cards(errors, contract.get("card_refs_and_hashes"))

    claimed_sha = contract.get("contract_sha256")
    if _nonempty_string(claimed_sha):
        if not _is_sha256(claimed_sha):
            errors.append("CONTRACT_SHA256_INVALID")
        else:
            expected_sha = canonical_json_sha256({k: v for k, v in contract.items() if k != "contract_sha256"})
            if claimed_sha != expected_sha:
                errors.append("CONTRACT_SHA256_MISMATCH")

    return sorted(set(errors))


def build_execution_contract(
    *, run_id: str, profile_code: str, profile_version: str, objective: str,
    authorized_scope: list[str], current_gate: str, allowed_actions: list[str],
    forbidden_actions: list[str], required_checks: list[str], required_evidence: list[str],
    closure_conditions: list[str], input_governance_ref: str,
    card_refs_and_hashes: list[dict[str, str]], adapter_ref: str,
    context_fingerprint: str, tool_permissions: list[str], executor_mode: str,
) -> dict[str, Any]:
    contract: dict[str, Any] = {
        "schema": SCHEMA,
        "run_id": run_id,
        "profile_code": profile_code,
        "profile_version": profile_version,
        "objective": objective,
        "authorized_scope": authorized_scope,
        "current_gate": current_gate,
        "allowed_actions": allowed_actions,
        "forbidden_actions": forbidden_actions,
        "required_checks": required_checks,
        "required_evidence": required_evidence,
        "closure_conditions": closure_conditions,
        "input_governance_ref": input_governance_ref,
        "card_refs_and_hashes": card_refs_and_hashes,
        "adapter_ref": adapter_ref,
        "context_fingerprint": context_fingerprint,
        "tool_permissions": tool_permissions,
        "executor_mode": executor_mode,
    }
    contract["contract_sha256"] = canonical_json_sha256(contract)
    errors = validate_execution_contract(contract)
    if errors:
        raise ExecutionContractError(";".join(errors))
    return contract


def validate_control_receipt(contract: dict[str, Any], receipt: Any) -> list[str]:
    errors = validate_execution_contract(contract)
    if errors:
        return ["SOURCE_CONTRACT_INVALID"] + errors
    if not isinstance(receipt, dict):
        return ["CONTROL_RECEIPT_NOT_OBJECT"]

    if receipt.get("receipt_type") != CONTROL_RECEIPT_TYPE:
        errors.append("CONTROL_RECEIPT_TYPE_INVALID")
    if receipt.get("run_id") != contract.get("run_id"):
        errors.append("CONTROL_RUN_ID_MISMATCH")
    if receipt.get("profile_code") != contract.get("profile_code"):
        errors.append("CONTROL_PROFILE_CODE_MISMATCH")
    if receipt.get("executor_mode") != contract.get("executor_mode"):
        errors.append("CONTROL_EXECUTOR_MODE_MISMATCH")
    if receipt.get("consumed_contract_sha256") != contract.get("contract_sha256"):
        errors.append("CONTROL_CONTRACT_SHA_NOT_CONSUMED")

    executed_checks = _validate_unique_string_list(errors, "executed_checks", receipt.get("executed_checks"))
    missing_checks = sorted(set(contract["required_checks"]) - set(executed_checks))
    if missing_checks:
        errors.append("REQUIRED_CHECKS_MISSING:" + ",".join(missing_checks))

    evidence_refs = receipt.get("evidence_refs")
    if not isinstance(evidence_refs, dict):
        errors.append("EVIDENCE_REFS_NOT_OBJECT")
    else:
        for key in contract["required_evidence"]:
            if not _nonempty_string(evidence_refs.get(key)):
                errors.append(f"REQUIRED_EVIDENCE_MISSING:{key}")

    closure_met = _validate_unique_string_list(errors, "closure_conditions_met", receipt.get("closure_conditions_met"))
    missing_closure = sorted(set(contract["closure_conditions"]) - set(closure_met))
    if missing_closure:
        errors.append("CLOSURE_CONDITIONS_MISSING:" + ",".join(missing_closure))

    action_log = _validate_unique_string_list(errors, "action_log", receipt.get("action_log"), allow_empty=True)
    unexpected_actions = sorted(set(action_log) - set(contract["allowed_actions"]))
    if unexpected_actions:
        errors.append("ACTION_OUTSIDE_ALLOWLIST:" + ",".join(unexpected_actions))
    forbidden_executed = sorted(set(action_log) & set(contract["forbidden_actions"]))
    if forbidden_executed:
        errors.append("FORBIDDEN_ACTION_EXECUTED:" + ",".join(forbidden_executed))

    scope_violations = receipt.get("scope_violations")
    if not isinstance(scope_violations, list):
        errors.append("SCOPE_VIOLATIONS_NOT_ARRAY")
    elif scope_violations:
        errors.append("SCOPE_VIOLATION_PRESENT")

    if receipt.get("downstream_authorized") is True:
        errors.append("CONTROL_SELF_AUTHORIZATION_FORBIDDEN")

    claimed_sha = receipt.get("receipt_sha256")
    if not _is_sha256(claimed_sha):
        errors.append("CONTROL_RECEIPT_SHA256_INVALID")
    else:
        expected_sha = canonical_json_sha256({k: v for k, v in receipt.items() if k != "receipt_sha256"})
        if claimed_sha != expected_sha:
            errors.append("CONTROL_RECEIPT_SHA256_MISMATCH")

    return sorted(set(errors))


def build_control_receipt(
    contract: dict[str, Any], *, executed_checks: list[str], evidence_refs: dict[str, str],
    closure_conditions_met: list[str], action_log: list[str], scope_violations: list[str] | None = None,
) -> dict[str, Any]:
    errors = validate_execution_contract(contract)
    if errors:
        raise ExecutionContractError("SOURCE_CONTRACT_INVALID:" + ";".join(errors))
    receipt: dict[str, Any] = {
        "receipt_type": CONTROL_RECEIPT_TYPE,
        "run_id": contract["run_id"],
        "profile_code": contract["profile_code"],
        "executor_mode": contract["executor_mode"],
        "consumed_contract_sha256": contract["contract_sha256"],
        "executed_checks": executed_checks,
        "evidence_refs": evidence_refs,
        "closure_conditions_met": closure_conditions_met,
        "action_log": action_log,
        "scope_violations": [] if scope_violations is None else scope_violations,
        "downstream_authorized": False,
    }
    receipt["receipt_sha256"] = canonical_json_sha256(receipt)
    return receipt
