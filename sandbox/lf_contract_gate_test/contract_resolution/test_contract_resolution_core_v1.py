#!/usr/bin/env python3
from __future__ import annotations

from contract_resolution_core_v1 import ContractResolutionError, resolve_contracts

PASS = 0
TOTAL = 16


def contract(operation_code: str, contract_code: str, status: str = "ACTIVE_ENFORCEMENT", **overrides):
    row = {
        "operation_code": operation_code,
        "contract_code": contract_code,
        "contract_path": f"supabase://public/lf_operation_contracts/{operation_code}/{contract_code}",
        "contract_sha": None,
        "required_before_write": [],
        "allowed": {},
        "blocked": [],
        "required_after_write": [],
        "status": status,
    }
    row.update(overrides)
    return row


def check(condition: bool, label: str) -> None:
    global PASS
    if not condition:
        raise AssertionError(label)
    PASS += 1


def expect_error(fn, token: str, label: str) -> None:
    global PASS
    try:
        fn()
    except ContractResolutionError as exc:
        if token not in str(exc):
            raise AssertionError(f"{label}:{exc}") from exc
        PASS += 1
        return
    raise AssertionError(label)


def main() -> None:
    one = resolve_contracts(operation_code="OP_A", contracts=[contract("OP_A", "C1")])
    check(one["contract_count"] == 1, "single active contract")
    check(one["operation_code"] == "OP_A", "operation identity preserved")

    two = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C2"), contract("OP_A", "C1")],
    )
    check(
        [row["contract_code"] for row in two["resolved_contracts"]] == ["C1", "C2"],
        "all active contracts returned in deterministic order",
    )

    statuses = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C1", "ACTIVE"), contract("OP_A", "C2", "ACTIVO")],
    )
    check(statuses["contract_count"] == 2, "legacy active statuses remain accepted")

    inactive = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "OLD", "SUPERSEDED"), contract("OP_A", "LIVE")],
    )
    check([row["contract_code"] for row in inactive["resolved_contracts"]] == ["LIVE"], "inactive excluded")

    other = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_B", "OTHER"), contract("OP_A", "OWN")],
    )
    check([row["contract_code"] for row in other["resolved_contracts"]] == ["OWN"], "other operation excluded")

    expect_error(
        lambda: resolve_contracts(operation_code="OP_A", contracts=[contract("OP_A", "OLD", "SUPERSEDED")]),
        "BLOCK_ACTIVE_CONTRACT_MISSING",
        "zero active must block",
    )
    expect_error(
        lambda: resolve_contracts(operation_code="OP_A", contracts=[contract("OP_A", "C1"), contract("OP_A", "C1")]),
        "DUPLICATE_ACTIVE_CONTRACT",
        "duplicate active identity must block",
    )
    expect_error(
        lambda: resolve_contracts(operation_code=" ", contracts=[]),
        "OPERATION_CODE",
        "blank operation must block",
    )
    expect_error(
        lambda: resolve_contracts(operation_code="OP_A", contracts="not-a-list"),
        "CONTRACTS_SHAPE",
        "invalid snapshot shape must block",
    )

    null_sha = resolve_contracts(operation_code="OP_A", contracts=[contract("OP_A", "C1")])
    check(null_sha["resolved_contracts"][0]["contract_sha"] is None, "null source sha is preserved, not invented")

    first = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C2"), contract("OP_A", "C1")],
    )
    second = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C1"), contract("OP_A", "C2")],
    )
    check(first["resolution_sha256"] == second["resolution_sha256"], "input order cannot change digest")

    role_payload = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C1", allowed={"base_contract_ref": "BASE-X"})],
    )
    check(
        role_payload["resolved_contracts"][0]["allowed"]["base_contract_ref"] == "BASE-X",
        "role-like metadata is preserved without interpretation",
    )

    changed_a = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C1", allowed={"x": 1})],
    )
    changed_b = resolve_contracts(
        operation_code="OP_A",
        contracts=[contract("OP_A", "C1", allowed={"x": 2})],
    )
    check(changed_a["resolution_sha256"] != changed_b["resolution_sha256"], "contract content drift changes resolution digest")

    no_eval = resolve_contracts(operation_code="OP_A", contracts=[contract("OP_A", "C1")])
    check("evaluations" not in no_eval, "resolver cannot produce Contract Check verdicts")
    check(no_eval["resolution_basis"] == "ALL_ACTIVE_CONTRACTS_FOR_OPERATION", "no ranking or one-of-N semantics")

    if PASS != TOTAL:
        raise AssertionError(f"unexpected pass count {PASS}/{TOTAL}")
    print(f"PASS_CONTRACT_RESOLUTION_CORE_V1={PASS}/{TOTAL}")


if __name__ == "__main__":
    main()
