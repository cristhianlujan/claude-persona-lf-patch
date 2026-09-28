#!/usr/bin/env python3
"""Neutral PASE dispatch planner over the canonical LF CI applicability plan.

The Router/Changeset Governance owns applicability. This module only verifies the
already-produced plan, validates the plan-level governance administrator identity,
derives dependency-safe carrier order from the canonical impact registry, and emits
a deterministic delegation packet. It does not run controls, resolve per-control
owners/runners, classify paths, evaluate contracts, mutate Git/Supabase, or persist
lifecycle state.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping

PLAN_SCHEMA_VERSION = "lf-ci-execution-plan/v2"
DISPATCH_SCHEMA_VERSION = "lf-pase-dispatch-plan/v1"
REGISTRY_VERSION = "lf-ci-control-impact-registry/v2"
GOVERNANCE_ADMIN_SCHEMA_VERSION = "lf-ci-governance-admin-identity/v1"
GOVERNANCE_SUPER_ADMIN = "LF_GOVERNANCE"
GOVERNANCE_SOURCE_CONTRACT_SCHEMA_VERSION = "lf-governance-super-admin/v1"
ROOT = Path(__file__).resolve().parents[3]
REGISTRY_PATH = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"


class PaseOrchestratorError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _load_registry(path: Path = REGISTRY_PATH) -> dict[str, dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise PaseOrchestratorError(f"FAIL_PASE_REGISTRY_READ:{exc.__class__.__name__}") from exc
    if not isinstance(data, dict) or data.get("schema_version") != REGISTRY_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_REGISTRY_SCHEMA")
    rows = data.get("controls")
    if not isinstance(rows, list) or not rows:
        raise PaseOrchestratorError("FAIL_PASE_REGISTRY_CONTROLS")
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise PaseOrchestratorError("FAIL_PASE_REGISTRY_CONTROL_ENTRY")
        control_id = row.get("control_id")
        carrier = row.get("carrier")
        dependencies = row.get("dependencies")
        if (
            not isinstance(control_id, str)
            or not control_id
            or not isinstance(carrier, str)
            or not carrier
            or not isinstance(dependencies, list)
            or any(not isinstance(dep, str) or not dep for dep in dependencies)
        ):
            raise PaseOrchestratorError("FAIL_PASE_REGISTRY_CONTROL_SHAPE")
        if control_id in result:
            raise PaseOrchestratorError(f"FAIL_PASE_REGISTRY_CONTROL_DUPLICATE:{control_id}")
        result[control_id] = {
            "carrier": carrier,
            "dependencies": tuple(dependencies),
        }
    return result


def _validate_governance_admin(plan: Mapping[str, Any]) -> dict[str, Any]:
    admin = plan.get("governance_admin")
    if not isinstance(admin, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_MISSING")

    required_fields = {
        "schema_version",
        "super_admin",
        "role",
        "status",
        "scope",
        "applicability_authority",
        "orchestrator_consumer",
        "source_contract_schema_version",
        "source_revision",
        "binding_materialized",
        "supabase_registered",
    }
    missing = sorted(required_fields - set(admin))
    if missing:
        raise PaseOrchestratorError(
            f"FAIL_PASE_GOVERNANCE_ADMIN_STRUCTURE:missing={','.join(missing)}"
        )

    if admin.get("schema_version") != GOVERNANCE_ADMIN_SCHEMA_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SCHEMA")
    if admin.get("super_admin") != GOVERNANCE_SUPER_ADMIN:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_IDENTITY")
    if admin.get("source_contract_schema_version") != GOVERNANCE_SOURCE_CONTRACT_SCHEMA_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SOURCE_CONTRACT")
    if admin.get("orchestrator_consumer") != "PASE_ORCHESTRATOR_V1":
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_CONSUMER")

    string_fields = (
        "role",
        "status",
        "scope",
        "applicability_authority",
        "source_revision",
    )
    for key in string_fields:
        value = admin.get(key)
        if not isinstance(value, str) or not value.strip():
            raise PaseOrchestratorError(f"FAIL_PASE_GOVERNANCE_ADMIN_FIELD:{key}")

    if re.fullmatch(r"[0-9a-f]{64}", admin["source_revision"]) is None:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SOURCE_REVISION")
    if not isinstance(admin.get("binding_materialized"), bool):
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_BINDING_MATERIALIZED")
    if not isinstance(admin.get("supabase_registered"), bool):
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SUPABASE_REGISTERED")

    # Preserve the upstream identity verbatim. PASE validates but does not
    # recalculate ownership, create per-control owners, or resolve owner-runners.
    return dict(admin)


def _validate_plan(
    plan: Mapping[str, Any],
    registry: Mapping[str, Mapping[str, Any]],
) -> tuple[list[str], dict[str, list[str]], dict[str, Any]]:
    if plan.get("schema_version") != PLAN_SCHEMA_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_PLAN_SCHEMA")
    governance_admin = _validate_governance_admin(plan)
    if plan.get("coverage_complete") is not True:
        raise PaseOrchestratorError("FAIL_PASE_PLAN_COVERAGE_INCOMPLETE")

    required = plan.get("required_controls")
    carrier_controls = plan.get("carrier_controls")
    if (
        not isinstance(required, list)
        or any(not isinstance(control, str) or not control for control in required)
        or len(required) != len(set(required))
        or required != sorted(required)
    ):
        raise PaseOrchestratorError("FAIL_PASE_REQUIRED_CONTROLS")
    if not isinstance(carrier_controls, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_CARRIER_CONTROLS")

    normalized: dict[str, list[str]] = {}
    control_to_carrier: dict[str, str] = {}
    for carrier, controls in carrier_controls.items():
        if not isinstance(carrier, str) or not carrier:
            raise PaseOrchestratorError("FAIL_PASE_CARRIER_ID")
        if (
            not isinstance(controls, list)
            or any(not isinstance(control, str) or not control for control in controls)
            or len(controls) != len(set(controls))
            or controls != sorted(controls)
        ):
            raise PaseOrchestratorError(f"FAIL_PASE_CARRIER_CONTROL_LIST:{carrier}")
        if not controls:
            raise PaseOrchestratorError(f"FAIL_PASE_EMPTY_CARRIER:{carrier}")
        normalized[carrier] = list(controls)
        for control in controls:
            if control in control_to_carrier:
                raise PaseOrchestratorError(f"FAIL_PASE_CONTROL_MULTI_CARRIER:{control}")
            control_to_carrier[control] = carrier

    required_set = set(required)
    assigned_set = set(control_to_carrier)
    missing = sorted(required_set - assigned_set)
    extra = sorted(assigned_set - required_set)
    if missing or extra:
        raise PaseOrchestratorError(
            "FAIL_PASE_CARRIER_COVERAGE:"
            f"missing={','.join(missing) or '-'}:"
            f"extra={','.join(extra) or '-'}"
        )

    unknown = sorted(required_set - set(registry))
    if unknown:
        raise PaseOrchestratorError(f"FAIL_PASE_UNKNOWN_CONTROL:{','.join(unknown)}")
    for control in required:
        expected_carrier = registry[control]["carrier"]
        observed_carrier = control_to_carrier[control]
        if observed_carrier != expected_carrier:
            raise PaseOrchestratorError(
                f"FAIL_PASE_CARRIER_DRIFT:{control}:expected={expected_carrier}:observed={observed_carrier}"
            )
    return list(required), normalized, governance_admin


def _carrier_order(
    required: list[str],
    carrier_controls: Mapping[str, list[str]],
    registry: Mapping[str, Mapping[str, Any]],
) -> list[str]:
    if not carrier_controls:
        return []

    control_to_carrier = {
        control: carrier
        for carrier, controls in carrier_controls.items()
        for control in controls
    }
    required_set = set(required)
    edges: dict[str, set[str]] = {carrier: set() for carrier in carrier_controls}
    indegree: dict[str, int] = {carrier: 0 for carrier in carrier_controls}

    for control in required:
        target_carrier = control_to_carrier[control]
        for dependency in registry[control]["dependencies"]:
            if dependency not in required_set:
                continue
            dependency_carrier = control_to_carrier[dependency]
            if dependency_carrier == target_carrier:
                continue
            if target_carrier not in edges[dependency_carrier]:
                edges[dependency_carrier].add(target_carrier)
                indegree[target_carrier] += 1

    ready = sorted(carrier for carrier, degree in indegree.items() if degree == 0)
    ordered: list[str] = []
    while ready:
        carrier = ready.pop(0)
        ordered.append(carrier)
        for downstream in sorted(edges[carrier]):
            indegree[downstream] -= 1
            if indegree[downstream] == 0:
                ready.append(downstream)
                ready.sort()

    if len(ordered) != len(carrier_controls):
        blocked = sorted(carrier for carrier, degree in indegree.items() if degree > 0)
        raise PaseOrchestratorError(f"FAIL_PASE_CARRIER_DEPENDENCY_CYCLE:{','.join(blocked)}")
    return ordered


def build_dispatch_plan(
    plan: Mapping[str, Any],
    *,
    registry_path: Path = REGISTRY_PATH,
) -> dict[str, Any]:
    """Build a deterministic, delegation-only PASE packet from an authoritative plan."""
    if not isinstance(plan, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_PLAN_NOT_OBJECT")
    registry = _load_registry(registry_path)
    required, carrier_controls, governance_admin = _validate_plan(plan, registry)
    ordered_carriers = _carrier_order(required, carrier_controls, registry)

    dispatches = [
        {
            "sequence": index,
            "carrier": carrier,
            "controls": carrier_controls[carrier],
            "mode": "DELEGATE_ONLY",
        }
        for index, carrier in enumerate(ordered_carriers, start=1)
    ]

    result: dict[str, Any] = {
        "schema_version": DISPATCH_SCHEMA_VERSION,
        "producer": "PASE_ORCHESTRATOR_V1",
        "source_plan_schema_version": PLAN_SCHEMA_VERSION,
        "source_plan_sha256": plan.get("plan_sha256"),
        "source_applicability_sha256": plan.get("applicability_sha256"),
        "source_evidence_sha256": plan.get("evidence_sha256"),
        "governance_admin": governance_admin,
        "applicability_authority": "UPSTREAM_PLAN_ONLY",
        "execution_semantics": "SEQUENTIAL_DELEGATION_ONLY",
        "required_controls": required,
        "dispatches": dispatches,
        "dispatch_count": len(dispatches),
        "control_count": len(required),
        "coverage_complete": True,
        "no_applicability_reclassification": True,
        "no_owner_recalculation": True,
        "no_per_control_owner_creation": True,
        "no_domain_execution": True,
    }
    result["dispatch_sha256"] = _sha256(result)
    return result
