#!/usr/bin/env python3
"""Neutral PASE dispatch planner over the canonical LF CI applicability plan.

Applicability stays upstream. This module validates the already-produced plan,
derives dependency-safe carrier order, and emits immutable execution envelopes.
It does not run controls, resolve owners/runners, classify paths, or persist state.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping

PLAN_SCHEMA_VERSION = "lf-ci-execution-plan/v2"
DISPATCH_SCHEMA_VERSION = "lf-pase-dispatch-plan/v1"
ENVELOPE_SCHEMA_VERSION = "lf-pase-execution-envelope/v1"
REGISTRY_VERSION = "lf-ci-control-impact-registry/v2"
GOVERNANCE_ADMIN_SCHEMA_VERSION = "lf-ci-governance-admin-identity/v1"
GOVERNANCE_SUPER_ADMIN = "LF_GOVERNANCE"
GOVERNANCE_SOURCE_CONTRACT_SCHEMA_VERSION = "lf-governance-super-admin/v1"
ROOT = Path(__file__).resolve().parents[3]
REGISTRY_PATH = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class PaseOrchestratorError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _require_hex(value: Any, pattern: re.Pattern[str], code: str) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise PaseOrchestratorError(code)
    return value


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
            not isinstance(control_id, str) or not control_id
            or not isinstance(carrier, str) or not carrier
            or not isinstance(dependencies, list)
            or any(not isinstance(dep, str) or not dep for dep in dependencies)
        ):
            raise PaseOrchestratorError("FAIL_PASE_REGISTRY_CONTROL_SHAPE")
        if control_id in result:
            raise PaseOrchestratorError(f"FAIL_PASE_REGISTRY_CONTROL_DUPLICATE:{control_id}")
        result[control_id] = {"carrier": carrier, "dependencies": tuple(dependencies)}
    return result


def _validate_governance_admin(plan: Mapping[str, Any]) -> dict[str, Any]:
    admin = plan.get("governance_admin")
    if not isinstance(admin, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_MISSING")
    required_fields = {
        "schema_version", "super_admin", "role", "status", "scope",
        "applicability_authority", "orchestrator_consumer",
        "source_contract_schema_version", "source_revision",
        "binding_materialized", "supabase_registered",
    }
    missing = sorted(required_fields - set(admin))
    if missing:
        raise PaseOrchestratorError(f"FAIL_PASE_GOVERNANCE_ADMIN_STRUCTURE:missing={','.join(missing)}")
    if admin.get("schema_version") != GOVERNANCE_ADMIN_SCHEMA_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SCHEMA")
    if admin.get("super_admin") != GOVERNANCE_SUPER_ADMIN:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_IDENTITY")
    if admin.get("source_contract_schema_version") != GOVERNANCE_SOURCE_CONTRACT_SCHEMA_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SOURCE_CONTRACT")
    if admin.get("orchestrator_consumer") != "PASE_ORCHESTRATOR_V1":
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_CONSUMER")
    for key in ("role", "status", "scope", "applicability_authority", "source_revision"):
        value = admin.get(key)
        if not isinstance(value, str) or not value.strip():
            raise PaseOrchestratorError(f"FAIL_PASE_GOVERNANCE_ADMIN_FIELD:{key}")
    _require_hex(admin["source_revision"], HEX64, "FAIL_PASE_GOVERNANCE_ADMIN_SOURCE_REVISION")
    if not isinstance(admin.get("binding_materialized"), bool):
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_BINDING_MATERIALIZED")
    if not isinstance(admin.get("supabase_registered"), bool):
        raise PaseOrchestratorError("FAIL_PASE_GOVERNANCE_ADMIN_SUPABASE_REGISTERED")
    if admin["binding_materialized"] is not False:
        raise PaseOrchestratorError("BLOCK_PASE_BINDING_MATERIALIZED_UNSUPPORTED")
    return dict(admin)


def _validate_plan(plan: Mapping[str, Any], registry: Mapping[str, Mapping[str, Any]]) -> tuple[list[str], dict[str, list[str]], dict[str, Any]]:
    if plan.get("schema_version") != PLAN_SCHEMA_VERSION:
        raise PaseOrchestratorError("FAIL_PASE_PLAN_SCHEMA")
    governance_admin = _validate_governance_admin(plan)
    if plan.get("coverage_complete") is not True:
        raise PaseOrchestratorError("FAIL_PASE_PLAN_COVERAGE_INCOMPLETE")
    required = plan.get("required_controls")
    carrier_controls = plan.get("carrier_controls")
    if not isinstance(required, list) or any(not isinstance(x, str) or not x for x in required) or len(required) != len(set(required)) or required != sorted(required):
        raise PaseOrchestratorError("FAIL_PASE_REQUIRED_CONTROLS")
    if not isinstance(carrier_controls, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_CARRIER_CONTROLS")
    normalized: dict[str, list[str]] = {}
    control_to_carrier: dict[str, str] = {}
    for carrier, controls in carrier_controls.items():
        if not isinstance(carrier, str) or not carrier:
            raise PaseOrchestratorError("FAIL_PASE_CARRIER_ID")
        if not isinstance(controls, list) or any(not isinstance(x, str) or not x for x in controls) or len(controls) != len(set(controls)) or controls != sorted(controls):
            raise PaseOrchestratorError(f"FAIL_PASE_CARRIER_CONTROL_LIST:{carrier}")
        if not controls:
            raise PaseOrchestratorError(f"FAIL_PASE_EMPTY_CARRIER:{carrier}")
        normalized[carrier] = list(controls)
        for control in controls:
            if control in control_to_carrier:
                raise PaseOrchestratorError(f"FAIL_PASE_CONTROL_MULTI_CARRIER:{control}")
            control_to_carrier[control] = carrier
    missing = sorted(set(required) - set(control_to_carrier))
    extra = sorted(set(control_to_carrier) - set(required))
    if missing or extra:
        raise PaseOrchestratorError(f"FAIL_PASE_CARRIER_COVERAGE:missing={','.join(missing) or '-'}:extra={','.join(extra) or '-'}")
    unknown = sorted(set(required) - set(registry))
    if unknown:
        raise PaseOrchestratorError(f"FAIL_PASE_UNKNOWN_CONTROL:{','.join(unknown)}")
    for control in required:
        if control_to_carrier[control] != registry[control]["carrier"]:
            raise PaseOrchestratorError(f"FAIL_PASE_CARRIER_DRIFT:{control}:expected={registry[control]['carrier']}:observed={control_to_carrier[control]}")
    return list(required), normalized, governance_admin


def _execution_context(plan: Mapping[str, Any], required: list[str]) -> dict[str, Any]:
    plan_digest = _require_hex(plan.get("plan_sha256"), HEX64, "FAIL_PASE_PLAN_DIGEST")
    applicability_digest = _require_hex(plan.get("applicability_sha256"), HEX64, "FAIL_PASE_APPLICABILITY_DIGEST")
    evidence_digest = _require_hex(plan.get("evidence_sha256"), HEX64, "FAIL_PASE_EVIDENCE_DIGEST")
    base_sha = _require_hex(plan.get("base_sha"), HEX40, "FAIL_PASE_BASE_SHA")
    head_sha = _require_hex(plan.get("head_sha"), HEX40, "FAIL_PASE_HEAD_SHA")
    source_revision = _require_hex(plan.get("authority_evidence_revision"), HEX40, "FAIL_PASE_SOURCE_REVISION")
    source_authority = plan.get("source_authority")
    if not isinstance(source_authority, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_SOURCE_AUTHORITY")
    if source_authority.get("resolved_revision") != source_revision:
        raise PaseOrchestratorError("FAIL_PASE_SOURCE_REVISION_DRIFT")
    enforcement = plan.get("pase_control_enforcement")
    if not isinstance(enforcement, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_ENFORCEMENT_MISSING")
    if enforcement.get("source_plan_sha256") != plan_digest:
        raise PaseOrchestratorError("FAIL_PASE_ENFORCEMENT_PLAN_DRIFT")
    if enforcement.get("required_controls") != required:
        raise PaseOrchestratorError("FAIL_PASE_ENFORCEMENT_REQUIRED_DRIFT")
    blocking = enforcement.get("blocking_controls")
    observe = enforcement.get("observe_only_controls")
    if not isinstance(blocking, list) or not isinstance(observe, list):
        raise PaseOrchestratorError("FAIL_PASE_ENFORCEMENT_PARTITION_SHAPE")
    if set(blocking) & set(observe) or set(blocking) | set(observe) != set(required):
        raise PaseOrchestratorError("FAIL_PASE_ENFORCEMENT_PARTITION")
    mode_by_control = {c: "ACTIVE_BLOCKING" for c in blocking}
    mode_by_control.update({c: "REPAIR_OBSERVE_ONLY" for c in observe})
    return {
        "schema_version": ENVELOPE_SCHEMA_VERSION,
        "authority_role": "TRANSPORT_ONLY",
        "writable_authority": False,
        "plan_digest": plan_digest,
        "applicability_digest": applicability_digest,
        "evidence_digest": evidence_digest,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "source_revision": source_revision,
        "source_currentness_decision": source_authority.get("decision"),
        "enforcement_policy_id": enforcement.get("policy_id"),
        "enforcement_result_sha256": enforcement.get("result_sha256"),
        "mode_by_control": mode_by_control,
        "no_applicability_reclassification": True,
        "no_owner_recalculation": True,
    }


def _carrier_dependencies(required: list[str], carrier_controls: Mapping[str, list[str]], registry: Mapping[str, Mapping[str, Any]]) -> dict[str, list[str]]:
    control_to_carrier = {control: carrier for carrier, controls in carrier_controls.items() for control in controls}
    required_set = set(required)
    deps: dict[str, set[str]] = {carrier: set() for carrier in carrier_controls}
    for control in required:
        target = control_to_carrier[control]
        for dependency in registry[control]["dependencies"]:
            if dependency in required_set:
                source = control_to_carrier[dependency]
                if source != target:
                    deps[target].add(source)
    return {carrier: sorted(values) for carrier, values in deps.items()}


def _carrier_order(required: list[str], carrier_controls: Mapping[str, list[str]], registry: Mapping[str, Mapping[str, Any]]) -> list[str]:
    deps = _carrier_dependencies(required, carrier_controls, registry)
    indegree = {carrier: len(values) for carrier, values in deps.items()}
    downstream: dict[str, set[str]] = {carrier: set() for carrier in carrier_controls}
    for carrier, values in deps.items():
        for dep in values:
            downstream[dep].add(carrier)
    ready = sorted(c for c, degree in indegree.items() if degree == 0)
    ordered: list[str] = []
    while ready:
        carrier = ready.pop(0)
        ordered.append(carrier)
        for nxt in sorted(downstream[carrier]):
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                ready.append(nxt)
                ready.sort()
    if len(ordered) != len(carrier_controls):
        blocked = sorted(c for c, degree in indegree.items() if degree > 0)
        raise PaseOrchestratorError(f"FAIL_PASE_CARRIER_DEPENDENCY_CYCLE:{','.join(blocked)}")
    return ordered


def build_dispatch_plan(plan: Mapping[str, Any], *, registry_path: Path = REGISTRY_PATH) -> dict[str, Any]:
    if not isinstance(plan, Mapping):
        raise PaseOrchestratorError("FAIL_PASE_PLAN_NOT_OBJECT")
    registry = _load_registry(registry_path)
    required, carrier_controls, governance_admin = _validate_plan(plan, registry)
    context = _execution_context(plan, required)
    ordered_carriers = _carrier_order(required, carrier_controls, registry)
    dependencies = _carrier_dependencies(required, carrier_controls, registry)
    dispatches = []
    for index, carrier in enumerate(ordered_carriers, start=1):
        controls = carrier_controls[carrier]
        envelope = {
            "plan_digest": context["plan_digest"],
            "base_sha": context["base_sha"],
            "head_sha": context["head_sha"],
            "source_revision": context["source_revision"],
            "sequence": index,
            "depends_on_carriers": dependencies[carrier],
            "carrier": carrier,
            "controls": controls,
            "enforcement_modes": {control: context["mode_by_control"][control] for control in controls},
        }
        identity_payload = {"schema_version": ENVELOPE_SCHEMA_VERSION, **envelope}
        dispatches.append({
            **envelope,
            "mode": "DELEGATE_ONLY",
            "execution_identity": _sha256({"kind": "PASE_EXECUTION", **identity_payload}),
            "idempotency_key": _sha256({"kind": "PASE_IDEMPOTENCY", **identity_payload}),
        })
    result: dict[str, Any] = {
        "schema_version": DISPATCH_SCHEMA_VERSION,
        "producer": "PASE_ORCHESTRATOR_V1",
        "source_plan_schema_version": PLAN_SCHEMA_VERSION,
        "source_plan_sha256": plan.get("plan_sha256"),
        "source_applicability_sha256": plan.get("applicability_sha256"),
        "source_evidence_sha256": plan.get("evidence_sha256"),
        "governance_admin": governance_admin,
        "execution_envelope_schema_version": ENVELOPE_SCHEMA_VERSION,
        "execution_envelope": {key: value for key, value in context.items() if key != "mode_by_control"},
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
        "no_parallel_authority": True,
    }
    result["dispatch_sha256"] = _sha256(result)
    return result
