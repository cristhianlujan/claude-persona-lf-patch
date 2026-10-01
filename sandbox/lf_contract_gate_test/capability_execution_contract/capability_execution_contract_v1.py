#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "capability_execution_contract_v1.json"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)


class ContractError(ValueError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha(value: Any) -> bool:
    return isinstance(value, str) and bool(SHA256_RE.fullmatch(value))


def load_contract() -> dict[str, Any]:
    data = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    validate_contract(data)
    return data


def validate_contract(contract: dict[str, Any]) -> None:
    if contract.get("schema_version") != "lf-capability-execution-contract/v1":
        raise ContractError("BLOCK_CONTRACT_SCHEMA")
    if contract.get("asset_code") != "CAPABILITY_EXECUTION_CONTRACT":
        raise ContractError("BLOCK_CONTRACT_IDENTITY")
    if contract.get("owner") != "LF_GOVERNANCE":
        raise ContractError("BLOCK_CONTRACT_OWNER")
    entry = contract.get("entry_guard")
    if not isinstance(entry, dict) or entry.get("required") is not True:
        raise ContractError("BLOCK_ENTRY_GUARD_REQUIRED")
    if entry.get("guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        raise ContractError("BLOCK_ENTRY_GUARD_CODE")
    if entry.get("accepted_decision") != "ORCHESTRATOR_ENTRY_ACCEPTED":
        raise ContractError("BLOCK_ENTRY_DECISION")
    if entry.get("local_shape_validation_is_authority") is not False:
        raise ContractError("BLOCK_LOCAL_SHAPE_AUTHORITY")
    inv = contract.get("invariants")
    if not isinstance(inv, dict):
        raise ContractError("BLOCK_INVARIANTS")
    for key in (
        "one_orchestrator_entry",
        "missing_or_invalid_orchestrator_receipt_fail_closed",
        "plan_digest_crossbind_required",
        "dispatch_scope_digest_required",
        "authority_refs_versioned_and_digested",
        "input_output_digests_required",
        "evidence_refs_required",
        "receipt_must_consume_exact_request",
        "self_authorization_forbidden",
        "contract_is_not_ledger",
        "contract_is_not_owner_registry",
        "contract_is_not_carrier",
        "contract_is_not_runtime_activation",
        "no_parallel_receipt_store",
    ):
        if inv.get(key) is not True:
            raise ContractError(f"BLOCK_INVARIANT:{key}")


def _validate_authority_refs(contract: dict[str, Any], value: Any) -> None:
    if not isinstance(value, dict):
        raise ContractError("BLOCK_AUTHORITY_REFS_SHAPE")
    required = contract["required_authority_refs"]
    if any(key not in value for key in required):
        raise ContractError("BLOCK_AUTHORITY_REF_MISSING")
    for key in required:
        row = value[key]
        if not isinstance(row, dict):
            raise ContractError(f"BLOCK_AUTHORITY_REF_SHAPE:{key}")
        if not _nonempty(row.get("ref")) or not _nonempty(row.get("revision")) or not _sha(row.get("digest")):
            raise ContractError(f"BLOCK_AUTHORITY_REF_INVALID:{key}")


def _validate_guard(contract: dict[str, Any], request: dict[str, Any]) -> None:
    guard = request.get("entry_guard_readback")
    if not isinstance(guard, dict) or guard.get("ready") is not True:
        raise ContractError("BLOCK_ORCHESTRATOR_ENTRY_GUARD")
    if guard.get("decision") != contract["entry_guard"]["accepted_decision"]:
        raise ContractError("BLOCK_ORCHESTRATOR_ENTRY_DECISION")
    if guard.get("guard_code") != contract["entry_guard"]["guard_code"]:
        raise ContractError("BLOCK_ORCHESTRATOR_ENTRY_GUARD_CODE")
    if guard.get("orchestrator_execution_id") != request.get("orchestrator_execution_id"):
        raise ContractError("BLOCK_ORCHESTRATOR_EXECUTION_CROSSBIND")
    if guard.get("receipt_id") != request.get("dispatch_receipt_id"):
        raise ContractError("BLOCK_DISPATCH_RECEIPT_CROSSBIND")


def validate_request(request: Any, contract: dict[str, Any] | None = None) -> None:
    contract = contract or load_contract()
    if not isinstance(request, dict):
        raise ContractError("BLOCK_REQUEST_SHAPE")
    if request.get("schema_version") != contract["request_schema"]:
        raise ContractError("BLOCK_REQUEST_SCHEMA")
    for key in ("orchestrator_execution_id", "consumer_execution_id", "capability_code", "input_ref", "source_revision"):
        if not _nonempty(request.get(key)):
            raise ContractError(f"BLOCK_REQUEST_IDENTITY:{key}")
    if not _sha(request.get("plan_digest")) or not _sha(request.get("input_digest")):
        raise ContractError("BLOCK_REQUEST_DIGEST")
    if not isinstance(request.get("dispatch_receipt_id"), str) or not UUID_RE.fullmatch(request["dispatch_receipt_id"]):
        raise ContractError("BLOCK_DISPATCH_RECEIPT_ID")
    scope = request.get("dispatch_scope")
    if not isinstance(scope, dict) or not scope:
        raise ContractError("BLOCK_DISPATCH_SCOPE")
    if request.get("dispatch_scope_digest") != digest(scope):
        raise ContractError("BLOCK_DISPATCH_SCOPE_DIGEST")
    _validate_guard(contract, request)
    _validate_authority_refs(contract, request.get("authority_refs"))
    claimed = request.get("request_digest")
    if not _sha(claimed):
        raise ContractError("BLOCK_REQUEST_DIGEST_FORMAT")
    expected = digest({k: v for k, v in request.items() if k != "request_digest"})
    if claimed != expected:
        raise ContractError("BLOCK_REQUEST_DIGEST_MISMATCH")


def build_request(*, orchestrator_execution_id: str, consumer_execution_id: str, capability_code: str,
                  plan_digest: str, dispatch_receipt_id: str, dispatch_scope: dict[str, Any],
                  entry_guard_readback: dict[str, Any], authority_refs: dict[str, Any],
                  input_ref: str, input_digest: str, source_revision: str) -> dict[str, Any]:
    request: dict[str, Any] = {
        "schema_version": "LF_CAPABILITY_EXECUTION_REQUEST_V1",
        "orchestrator_execution_id": orchestrator_execution_id,
        "consumer_execution_id": consumer_execution_id,
        "capability_code": capability_code,
        "plan_digest": plan_digest,
        "dispatch_receipt_id": dispatch_receipt_id,
        "dispatch_scope": dispatch_scope,
        "dispatch_scope_digest": digest(dispatch_scope),
        "entry_guard_readback": entry_guard_readback,
        "authority_refs": authority_refs,
        "input_ref": input_ref,
        "input_digest": input_digest,
        "source_revision": source_revision,
    }
    request["request_digest"] = digest(request)
    validate_request(request)
    return request


def validate_receipt(request: dict[str, Any], receipt: Any, contract: dict[str, Any] | None = None) -> None:
    contract = contract or load_contract()
    validate_request(request, contract)
    if not isinstance(receipt, dict):
        raise ContractError("BLOCK_RECEIPT_SHAPE")
    if receipt.get("schema_version") != contract["receipt_schema"]:
        raise ContractError("BLOCK_RECEIPT_SCHEMA")
    for key in contract["cross_bindings"]:
        expected = request.get(key)
        observed = receipt.get(key)
        if observed != expected:
            raise ContractError(f"BLOCK_RECEIPT_CROSSBIND:{key}")
    if receipt.get("consumed_request_digest") != request.get("request_digest"):
        raise ContractError("BLOCK_REQUEST_CONSUMPTION")
    if not _nonempty(receipt.get("output_ref")) or not _sha(receipt.get("output_digest")):
        raise ContractError("BLOCK_OUTPUT_EVIDENCE")
    evidence = receipt.get("evidence_refs")
    if not isinstance(evidence, list) or not evidence:
        raise ContractError("BLOCK_EVIDENCE_REFS")
    seen: set[str] = set()
    for row in evidence:
        if not isinstance(row, dict) or not _nonempty(row.get("ref")) or not _sha(row.get("digest")):
            raise ContractError("BLOCK_EVIDENCE_REF_INVALID")
        if row["ref"] in seen:
            raise ContractError("BLOCK_EVIDENCE_REF_DUPLICATE")
        seen.add(row["ref"])
    if receipt.get("self_authorized") is True or receipt.get("downstream_authorized") is True:
        raise ContractError("BLOCK_SELF_AUTHORIZATION")
    claimed = receipt.get("receipt_digest")
    if not _sha(claimed):
        raise ContractError("BLOCK_RECEIPT_DIGEST_FORMAT")
    expected = digest({k: v for k, v in receipt.items() if k != "receipt_digest"})
    if claimed != expected:
        raise ContractError("BLOCK_RECEIPT_DIGEST_MISMATCH")


def build_receipt(request: dict[str, Any], *, output_ref: str, output_digest: str,
                  evidence_refs: list[dict[str, str]]) -> dict[str, Any]:
    validate_request(request)
    receipt: dict[str, Any] = {
        "schema_version": "LF_CAPABILITY_EXECUTION_RECEIPT_V1",
        "orchestrator_execution_id": request["orchestrator_execution_id"],
        "consumer_execution_id": request["consumer_execution_id"],
        "capability_code": request["capability_code"],
        "plan_digest": request["plan_digest"],
        "dispatch_receipt_id": request["dispatch_receipt_id"],
        "consumed_request_digest": request["request_digest"],
        "authority_refs": request["authority_refs"],
        "input_digest": request["input_digest"],
        "output_ref": output_ref,
        "output_digest": output_digest,
        "evidence_refs": evidence_refs,
        "source_revision": request["source_revision"],
        "self_authorized": False,
        "downstream_authorized": False,
    }
    receipt["receipt_digest"] = digest(receipt)
    validate_receipt(request, receipt)
    return receipt
