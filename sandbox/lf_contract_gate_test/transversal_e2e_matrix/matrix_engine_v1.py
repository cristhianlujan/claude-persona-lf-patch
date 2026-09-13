#!/usr/bin/env python3
"""Deterministic LF transversal Router-to-Terminal assurance matrix.

This module is intentionally side-effect free. It evaluates a source snapshot produced
from the canonical LF operation/router/contract/policy surfaces and returns a fail-closed
closure decision. Product-specific wrappers (S26/S30) consume the same engine.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Iterable, List

PASS = "PASS"
BLOCK = "BLOCK"
PENDING = "PENDING"


def _productionish(status: str) -> bool:
    s = (status or "").upper()
    return "PRODUCCION" in s or s in {"ACTIVE", "ACTIVO", "SANDBOX_ACTIVE"}


def classify_unrouted(op: Dict[str, Any]) -> str:
    status = str(op.get("status") or "").upper()
    family = str(op.get("operation_family") or "").upper()
    op_type = str(op.get("operation_type") or "").upper()

    if status.startswith("CANDIDATO") or status.startswith("CANDIDATE"):
        return "CANDIDATE_INACTIVE"
    if op_type == "SCHEDULER_DRIVEN":
        return "SCHEDULER"
    if (
        "ENFORCEMENT" in family
        or op_type in {
            "CONTRACT_GATE",
            "REGRESSION_SUITE",
            "SANDBOX_TEST",
            "TEST_RECORDS_CLASSIFICATION",
            "TEST_RECORDS_SANITIZATION",
            "INTERNAL_ENFORCEMENT",
        }
    ):
        return "CONTROL_PLANE"
    if op_type == "SKILL_EXECUTION":
        return "INTERNAL_SUBOPERATION"
    if _productionish(status):
        return "INTERNAL_PROTOCOL"
    return "UNCLASSIFIED"


def direct_operation_findings(op: Dict[str, Any]) -> List[str]:
    findings: List[str] = []
    code = str(op.get("operation_code") or "<UNKNOWN>")
    route_count = int(op.get("active_route_count") or 0)
    contracts = int(op.get("active_contract_count") or 0)
    steps = int(op.get("active_step_count") or 0)
    required_policies = int(op.get("required_policy_count") or 0)
    resolved_policies = int(op.get("resolved_policy_count") or 0)

    if route_count <= 0:
        findings.append(f"{code}:DIRECT_OPERATION_WITHOUT_ACTIVE_ROUTE")
    if contracts <= 0:
        findings.append(f"{code}:ACTIVE_CONTRACT_MISSING")
    if steps <= 0:
        findings.append(f"{code}:ACTIVE_STEPS_MISSING")
    if required_policies != resolved_policies:
        findings.append(
            f"{code}:REQUIRED_POLICY_RESOLUTION_MISMATCH:{required_policies}!={resolved_policies}"
        )

    unreachable = list(op.get("unreachable_required_steps") or [])
    for step in unreachable:
        findings.append(f"{code}:REQUIRED_STEP_UNREACHABLE:{step}")

    missing_targets = list(op.get("missing_block_targets") or [])
    for target in missing_targets:
        findings.append(f"{code}:BLOCK_TARGET_MISSING:{target}")

    self_loops = list(op.get("self_loops") or [])
    for loop in self_loops:
        findings.append(f"{code}:UNJUSTIFIED_SELF_LOOP:{loop}")

    adversarial = str(op.get("invalid_mode_verdict") or "UNKNOWN")
    if adversarial in {"BYPASS_AND_READY", "POLICY_FILTER_BYPASS_BUT_OTHER_GATE_BLOCKS"}:
        findings.append(f"{code}:INVALID_DISTRIBUTION_MODE_POLICY_BYPASS:{adversarial}")
    elif adversarial == "UNKNOWN":
        findings.append(f"{code}:INVALID_DISTRIBUTION_MODE_NOT_PROVEN")

    return findings


def inspect_route_findings(routes: Iterable[Dict[str, Any]]) -> List[str]:
    findings: List[str] = []
    for route in routes:
        asset = str(route.get("asset_type") or "<UNKNOWN>")
        action = str(route.get("action_code") or "<UNKNOWN>")
        resolution = str(route.get("operation_resolution") or "")
        op_code = route.get("operation_code")
        if action == "ASSET_INSPECTION" and resolution == "NONE" and not op_code:
            continue
        findings.append(f"{asset}:{action}:UNPROVEN_NON_EXECUTION_ROUTE")
    return findings


def unrouted_operation_findings(op: Dict[str, Any]) -> List[str]:
    findings: List[str] = []
    code = str(op.get("operation_code") or "<UNKNOWN>")
    cls = str(op.get("classification") or classify_unrouted(op))
    expected = classify_unrouted(op)
    if cls != expected:
        findings.append(f"{code}:CLASSIFICATION_MISMATCH:{cls}!={expected}")
    if cls == "UNCLASSIFIED":
        findings.append(f"{code}:UNROUTED_OPERATION_UNCLASSIFIED")
        return findings

    provenance = str(op.get("provenance_status") or "UNKNOWN")
    if cls in {"INTERNAL_SUBOPERATION", "INTERNAL_PROTOCOL", "SCHEDULER", "CONTROL_PLANE"}:
        if provenance not in {"PROVEN", "NOT_APPLICABLE_TEST_ONLY"}:
            findings.append(f"{code}:INTERNAL_ENTRY_PROVENANCE_NOT_PROVEN:{provenance}")
    return findings


def reservation_findings(reserve_case: Dict[str, Any]) -> List[str]:
    """Separate Router-authority provenance from policy/registry trigger protections."""
    findings: List[str] = []
    if reserve_case.get("router_provenance_required") is not True:
        findings.append("DIRECT_OPERATION_RESERVATION_ROUTER_PROVENANCE_NOT_REQUIRED")
    if reserve_case.get("policy_snapshot_on_insert") is not True:
        findings.append("DIRECT_OPERATION_RESERVATION_POLICY_SNAPSHOT_NOT_ENFORCED")
    if reserve_case.get("required_policy_resolution_guard") is not True:
        findings.append("DIRECT_OPERATION_RESERVATION_REQUIRED_POLICY_GUARD_NOT_ENFORCED")
    if reserve_case.get("policy_snapshot_immutable_and_currentness_guard") is not True:
        findings.append("DIRECT_OPERATION_RESERVATION_POLICY_CURRENTNESS_GUARD_NOT_ENFORCED")
    if reserve_case.get("registered_operation_required") is not True:
        findings.append("DIRECT_OPERATION_RESERVATION_REGISTRY_GUARD_NOT_ENFORCED")
    return findings


def evaluate(snapshot: Dict[str, Any]) -> Dict[str, Any]:
    findings: List[str] = []

    direct = list(snapshot.get("direct_operations") or [])
    inspections = list(snapshot.get("inspection_routes") or [])
    unrouted = list(snapshot.get("unrouted_operations") or [])

    for op in direct:
        findings.extend(direct_operation_findings(op))
    findings.extend(inspect_route_findings(inspections))
    for op in unrouted:
        findings.extend(unrouted_operation_findings(op))

    target_case = snapshot.get("target_authority_case") or {}
    if target_case.get("status") == "OVERRIDE_CONFIRMED":
        findings.append("ROUTER_TARGET_HINT_CAN_OVERRIDE_CANONICAL_TARGET")
    elif target_case.get("status") not in {"BLOCKED", "CANONICAL_TARGET_WINS"}:
        findings.append("ROUTER_TARGET_AUTHORITY_NOT_PROVEN")

    reserve_case = snapshot.get("direct_reservation_case") or {}
    findings.extend(reservation_findings(reserve_case))

    meta = snapshot.get("metadata") or {}
    expected_ops = int(meta.get("operation_count") or 0)
    expected_routed_ops = int(meta.get("routed_operation_count") or 0)
    expected_unrouted_ops = int(meta.get("unrouted_operation_count") or 0)
    expected_route_rows = int(meta.get("active_route_count") or 0)
    observed_route_rows = sum(int(x.get("active_route_count") or 0) for x in direct) + len(inspections)

    coverage = {
        "operations_expected": expected_ops,
        "operations_accounted": len(direct) + len(unrouted),
        "routed_operations_expected": expected_routed_ops,
        "routed_operations_accounted": len(direct),
        "unrouted_operations_expected": expected_unrouted_ops,
        "unrouted_operations_accounted": len(unrouted),
        "active_route_rows_expected": expected_route_rows,
        "active_route_rows_accounted": observed_route_rows,
    }
    if coverage["operations_expected"] != coverage["operations_accounted"]:
        findings.append("MATRIX_OPERATION_UNIVERSE_INCOMPLETE")
    if coverage["routed_operations_expected"] != coverage["routed_operations_accounted"]:
        findings.append("MATRIX_ROUTED_OPERATION_UNIVERSE_INCOMPLETE")
    if coverage["unrouted_operations_expected"] != coverage["unrouted_operations_accounted"]:
        findings.append("MATRIX_UNROUTED_OPERATION_UNIVERSE_INCOMPLETE")
    if coverage["active_route_rows_expected"] != coverage["active_route_rows_accounted"]:
        findings.append("MATRIX_ACTIVE_ROUTE_UNIVERSE_INCOMPLETE")

    unique_findings = sorted(set(findings))
    reservation_guards = {
        "router_provenance_required": reserve_case.get("router_provenance_required") is True,
        "policy_snapshot_on_insert": reserve_case.get("policy_snapshot_on_insert") is True,
        "required_policy_resolution_guard": reserve_case.get("required_policy_resolution_guard") is True,
        "policy_snapshot_immutable_and_currentness_guard": reserve_case.get("policy_snapshot_immutable_and_currentness_guard") is True,
        "registered_operation_required": reserve_case.get("registered_operation_required") is True,
    }
    return {
        "matrix_version": "transversal-e2e-matrix/v1",
        "status": PASS if not unique_findings else BLOCK,
        "finding_count": len(unique_findings),
        "findings": unique_findings,
        "coverage": coverage,
        "direct_reservation_guards": reservation_guards,
    }


def evaluate_file(path: str | Path) -> Dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return evaluate(data)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("snapshot")
    args = parser.parse_args()
    print(json.dumps(evaluate_file(args.snapshot), indent=2, sort_keys=True))
