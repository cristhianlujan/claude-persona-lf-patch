#!/usr/bin/env python3
"""Pure deterministic Contract Resolution core.

Contract Resolution receives an already-decided operation_code plus an authority
snapshot of operation contracts. It returns every active contract for that
operation, in deterministic order. It does not route operations, rank contracts,
infer primary/supplemental roles, or evaluate contract terms.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping, Sequence

SCHEMA_VERSION = "lf-contract-resolution-result/v1"
ACTIVE_STATUSES = ("ACTIVE_ENFORCEMENT", "ACTIVE", "ACTIVO")
REQUIRED_CONTRACT_KEYS = (
    "operation_code",
    "contract_code",
    "contract_path",
    "contract_sha",
    "required_before_write",
    "allowed",
    "blocked",
    "required_after_write",
    "status",
)


class ContractResolutionError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def resolve_contracts(
    *,
    operation_code: str,
    contracts: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Resolve all active contracts for one already-resolved operation.

    `contracts` is an authority snapshot, not a set of semantic evaluations.
    The resolver preserves the exact active rows and only applies identity,
    status and deterministic-order rules.
    """
    if not isinstance(operation_code, str) or not operation_code.strip():
        raise ContractResolutionError("FAIL_CONTRACT_RESOLUTION_OPERATION_CODE")
    operation_code = operation_code.strip()

    if not isinstance(contracts, (list, tuple)):
        raise ContractResolutionError("FAIL_CONTRACT_RESOLUTION_CONTRACTS_SHAPE")

    resolved: list[dict[str, Any]] = []
    seen: set[str] = set()

    for index, row in enumerate(contracts):
        if not isinstance(row, Mapping):
            raise ContractResolutionError(f"FAIL_CONTRACT_RESOLUTION_ROW_SHAPE:{index}")

        row_operation = row.get("operation_code")
        status = row.get("status")
        contract_code = row.get("contract_code")
        if (
            not isinstance(row_operation, str)
            or not isinstance(status, str)
            or not isinstance(contract_code, str)
            or not contract_code
        ):
            raise ContractResolutionError(f"FAIL_CONTRACT_RESOLUTION_ROW_IDENTITY:{index}")

        if row_operation != operation_code or status not in ACTIVE_STATUSES:
            continue

        missing = [key for key in REQUIRED_CONTRACT_KEYS if key not in row]
        if missing:
            raise ContractResolutionError(
                "FAIL_CONTRACT_RESOLUTION_ACTIVE_ROW_INCOMPLETE:"
                f"{contract_code}:{','.join(missing)}"
            )

        if contract_code in seen:
            raise ContractResolutionError(
                f"FAIL_CONTRACT_RESOLUTION_DUPLICATE_ACTIVE_CONTRACT:{contract_code}"
            )
        seen.add(contract_code)
        resolved.append(dict(row))

    resolved.sort(key=lambda row: row["contract_code"])
    if not resolved:
        raise ContractResolutionError(f"BLOCK_ACTIVE_CONTRACT_MISSING:{operation_code}")

    result: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "operation_code": operation_code,
        "resolution_basis": "ALL_ACTIVE_CONTRACTS_FOR_OPERATION",
        "active_statuses": list(ACTIVE_STATUSES),
        "contract_count": len(resolved),
        "resolved_contracts": resolved,
    }
    result["resolution_sha256"] = _sha256(result)
    return result
