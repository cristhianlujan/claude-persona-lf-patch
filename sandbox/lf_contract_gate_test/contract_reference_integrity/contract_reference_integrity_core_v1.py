#!/usr/bin/env python3
"""Pure deterministic core for LF operation contract/reference integrity.

This module does not resolve applicability, execute sibling controls, call a
runtime, read GitHub, query Supabase, or judge downstream execution results.
It validates only a caller-supplied snapshot of the formal LF operation
contract surfaces.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter, defaultdict
from typing import Any, Mapping

SCHEMA_VERSION = "lf-contract-reference-integrity-snapshot/v1"
RESULT_SCHEMA_VERSION = "lf-contract-reference-integrity-result/v1"
ACTIVE_STATUSES = frozenset({"ACTIVE", "ACTIVO", "ACTIVE_ENFORCEMENT"})
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
TERMINALS = frozenset({"STOP"})


class SnapshotError(ValueError):
    pass


def _require_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise SnapshotError(f"{label}_must_be_object")
    return value


def _require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise SnapshotError(f"{label}_must_be_array")
    return value


def _text(row: Mapping[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else ""


def _active(row: Mapping[str, Any]) -> bool:
    return _text(row, "status") in ACTIVE_STATUSES


def _canonical_sha256(value: Mapping[str, Any]) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def evaluate(snapshot: Mapping[str, Any]) -> dict[str, Any]:
    snap = _require_object(snapshot, "snapshot")
    if snap.get("schema_version") != SCHEMA_VERSION:
        raise SnapshotError("snapshot_schema_version_invalid")

    operation = _require_object(snap.get("operation"), "operation")
    operation_code = _text(operation, "operation_code")
    if not operation_code:
        raise SnapshotError("operation_code_missing")

    contracts = [_require_object(v, "contract") for v in _require_list(snap.get("contracts"), "contracts")]
    steps = [_require_object(v, "step") for v in _require_list(snap.get("steps"), "steps")]
    step_contracts = [
        _require_object(v, "step_contract")
        for v in _require_list(snap.get("step_contracts"), "step_contracts")
    ]
    judge_bindings = [
        _require_object(v, "judge_binding")
        for v in _require_list(snap.get("judge_bindings"), "judge_bindings")
    ]
    judges = [_require_object(v, "judge") for v in _require_list(snap.get("judges"), "judges")]
    policies = [_require_object(v, "policy") for v in _require_list(snap.get("policies"), "policies")]

    failures: list[dict[str, Any]] = []

    def fail(code: str, detail: Any = None) -> None:
        row: dict[str, Any] = {"code": code}
        if detail is not None:
            row["detail"] = detail
        failures.append(row)

    active_contracts = [row for row in contracts if _active(row)]
    if not active_contracts:
        fail("FAIL_ACTIVE_CONTRACT_MISSING")
    contract_codes = [_text(row, "contract_code") for row in active_contracts]
    for code, count in sorted(Counter(contract_codes).items()):
        if not code:
            fail("FAIL_CONTRACT_CODE_MISSING")
        elif count != 1:
            fail("FAIL_CONTRACT_CODE_DUPLICATE", {"contract_code": code, "count": count})
    for row in active_contracts:
        code = _text(row, "contract_code")
        if not _text(row, "contract_path"):
            fail("FAIL_CONTRACT_PATH_MISSING", code or None)
        sha = _text(row, "contract_sha")
        if SHA64_RE.fullmatch(sha) is None:
            fail("FAIL_CONTRACT_SHA_MISSING_OR_INVALID", code or None)

    active_steps = [row for row in steps if row.get("active") is True]
    if not active_steps:
        fail("FAIL_ACTIVE_STEPS_MISSING")

    step_ids = [_text(row, "step_id") for row in active_steps]
    for step_id, count in sorted(Counter(step_ids).items()):
        if not step_id:
            fail("FAIL_STEP_ID_MISSING")
        elif count != 1:
            fail("FAIL_ACTIVE_STEP_DUPLICATE", {"step_id": step_id, "count": count})

    execution_orders: list[int] = []
    for row in active_steps:
        value = row.get("execution_order")
        if not isinstance(value, int) or value < 1:
            fail("FAIL_STEP_EXECUTION_ORDER_INVALID", _text(row, "step_id") or None)
        else:
            execution_orders.append(value)
    for order, count in sorted(Counter(execution_orders).items()):
        if count != 1:
            fail("FAIL_STEP_EXECUTION_ORDER_DUPLICATE", {"execution_order": order, "count": count})

    active_step_contracts = [row for row in step_contracts if _active(row)]
    by_step_contract: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for row in active_step_contracts:
        by_step_contract[_text(row, "step_id")].append(row)

    active_step_ids = set(step_ids)
    required_steps = [row for row in active_steps if row.get("required") is True]
    for step in required_steps:
        step_id = _text(step, "step_id")
        matches = by_step_contract.get(step_id, [])
        if len(matches) != 1:
            fail("FAIL_REQUIRED_STEP_CONTRACT_CARDINALITY", {"step_id": step_id, "count": len(matches)})
            continue
        contract = matches[0]
        if contract.get("step_order") != step.get("step_order"):
            fail("FAIL_STEP_CONTRACT_ORDER_MISMATCH", step_id)
        if contract.get("execution_order") != step.get("execution_order"):
            fail("FAIL_STEP_CONTRACT_EXECUTION_ORDER_MISMATCH", step_id)
        if not _text(contract, "contract_code"):
            fail("FAIL_STEP_CONTRACT_CODE_MISSING", step_id)
        if not _text(contract, "resolver_ref"):
            fail("FAIL_STEP_RESOLVER_REF_MISSING", step_id)
        if not _text(contract, "mini_judge_code"):
            fail("FAIL_STEP_MINI_JUDGE_CODE_MISSING", step_id)

    for row in active_step_contracts:
        step_id = _text(row, "step_id")
        if step_id and step_id not in active_step_ids:
            fail("FAIL_ORPHAN_ACTIVE_STEP_CONTRACT", step_id)
        for field in ("next_if_pass", "next_if_blocked"):
            target = _text(row, field)
            if not target or target in TERMINALS:
                continue
            if target == step_id:
                fail("FAIL_STEP_TRANSITION_SELF_LOOP", {"step_id": step_id, "field": field})
            elif target not in active_step_ids:
                fail("FAIL_STEP_TRANSITION_TARGET_MISSING", {"step_id": step_id, "field": field, "target": target})

    active_bindings = [row for row in judge_bindings if _active(row)]
    bindings_by_step: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for row in active_bindings:
        bindings_by_step[_text(row, "step_id")].append(row)

    active_judges = [row for row in judges if _active(row)]
    judge_codes = {_text(row, "judge_code") for row in active_judges if _text(row, "judge_code")}
    for step in required_steps:
        step_id = _text(step, "step_id")
        matches = bindings_by_step.get(step_id, [])
        if len(matches) != 1:
            fail("FAIL_REQUIRED_STEP_JUDGE_BINDING_CARDINALITY", {"step_id": step_id, "count": len(matches)})
            continue
        binding = matches[0]
        if binding.get("step_order") != step.get("step_order"):
            fail("FAIL_JUDGE_BINDING_ORDER_MISMATCH", step_id)
        judge_code = _text(binding, "judge_code")
        if not judge_code:
            fail("FAIL_JUDGE_CODE_MISSING", step_id)
        elif judge_code not in judge_codes:
            fail("FAIL_ACTIVE_JUDGE_MISSING", {"step_id": step_id, "judge_code": judge_code})

    required_policies = [row for row in policies if row.get("required") is True]
    policy_ids: list[str] = []
    for row in required_policies:
        code = _text(row, "policy_code")
        role = _text(row, "policy_role")
        policy_ids.append(f"{role}:{code}")
        if not code or not role:
            fail("FAIL_REQUIRED_POLICY_IDENTITY_MISSING")
        sha = _text(row, "policy_sha")
        if SHA64_RE.fullmatch(sha) is None:
            fail("FAIL_REQUIRED_POLICY_UNRESOLVED", {"policy_code": code, "policy_role": role})
    for identity, count in sorted(Counter(policy_ids).items()):
        if identity != ":" and count != 1:
            fail("FAIL_REQUIRED_POLICY_DUPLICATE", {"policy": identity, "count": count})

    supplied_revision = _text(snap, "operation_revision_sha256")
    if supplied_revision and SHA64_RE.fullmatch(supplied_revision) is None:
        fail("FAIL_OPERATION_REVISION_SHA_INVALID")

    verdict = "PASS" if not failures else "BLOCK"
    result: dict[str, Any] = {
        "schema_version": RESULT_SCHEMA_VERSION,
        "verdict": verdict,
        "operation_code": operation_code,
        "formal_reference_scope": {
            "contracts": True,
            "required_step_contracts": True,
            "judge_bindings": True,
            "required_policies": True,
            "step_transition_targets": True,
            "resolver_ref_semantic_resolution": False,
        },
        "counts": {
            "active_contracts": len(active_contracts),
            "active_steps": len(active_steps),
            "required_steps": len(required_steps),
            "active_step_contracts": len(active_step_contracts),
            "active_judge_bindings": len(active_bindings),
            "active_judges": len(active_judges),
            "required_policies": len(required_policies),
            "failures": len(failures),
        },
        "failures": failures,
        "snapshot_sha256": _canonical_sha256(snap),
    }
    if supplied_revision:
        result["operation_revision_sha256"] = supplied_revision
    return result


def main() -> int:
    import argparse
    from pathlib import Path

    parser = argparse.ArgumentParser()
    parser.add_argument("snapshot")
    parser.add_argument("--output")
    args = parser.parse_args()
    snapshot = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
    result = evaluate(snapshot)
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if result["verdict"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
