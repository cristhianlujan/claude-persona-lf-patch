#!/usr/bin/env python3
"""Temporary PASE enforcement projection while legacy validators are repaired.

Applicability remains owned by CHANGESET_GOVERNANCE_LF_V1 / lf-ci-execution-plan/v2.
This module never classifies paths and never executes controls. It projects the
already-applicable control set into merge-blocking vs observe-only states.

A legacy control may return to merge-blocking only with explicit re-entry
evidence. Structural governance (path admission, plan schema/coverage, policy
coverage, and exact-head qualification) remains fail-closed outside this policy.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping

POLICY_SCHEMA = "lf-pase-control-repair-policy/v1"
PLAN_SCHEMA = "lf-ci-execution-plan/v2"
RESULT_SCHEMA = "lf-pase-control-enforcement/v1"
AUTHORITY = "CHANGESET_GOVERNANCE_LF_V1"
POLICY_ID = "PASE_CONTROL_REPAIR_QUARANTINE_V1"
POLICY_PATH = Path(__file__).with_name("lf_pase_control_repair_quarantine_v1.json")
STATES = {"REPAIR_OBSERVE_ONLY", "ACTIVE_BLOCKING"}
CONTROL_ID = re.compile(r"^[A-Z][A-Z0-9_]*$")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REENTRY_REQUIRED = (
    "CANDIDATE_QUALIFIED",
    "OWNER_RUNNER_BOUND",
    "EQUIVALENT_REPLAY_PASS",
    "EXACT_HEAD_READBACK_PASS",
)


class RepairQuarantineError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _sorted_unique_controls(value: Any) -> bool:
    return (
        isinstance(value, list)
        and value == sorted(value)
        and len(value) == len(set(value))
        and all(isinstance(v, str) and CONTROL_ID.fullmatch(v) for v in value)
    )


def _validate_reentry_evidence(value: Any) -> None:
    if not isinstance(value, Mapping):
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_EVIDENCE_MISSING")
    expected = {
        "qualification_verdict",
        "qualification_head_sha",
        "owner_runner_binding",
        "equivalent_replay",
        "exact_head_readback",
    }
    if set(value) != expected:
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_EVIDENCE_SHAPE")
    if value.get("qualification_verdict") != "CANDIDATE_QUALIFIED":
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_NOT_QUALIFIED")
    head = value.get("qualification_head_sha")
    if not isinstance(head, str) or SHA40.fullmatch(head) is None:
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_HEAD")
    if value.get("owner_runner_binding") != "PASS":
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_OWNER_RUNNER")
    if value.get("equivalent_replay") != "PASS":
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_REPLAY")
    if value.get("exact_head_readback") != "PASS":
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_READBACK")


def validate_policy(policy: Mapping[str, Any], *, control_universe: list[str]) -> dict[str, Mapping[str, Any]]:
    if not isinstance(policy, Mapping) or policy.get("schema_version") != POLICY_SCHEMA:
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_SCHEMA")
    if policy.get("policy_id") != POLICY_ID or policy.get("authority") != AUTHORITY:
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_AUTHORITY")
    if policy.get("mode") != "TEMPORARY_REPAIR_WINDOW":
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_MODE")
    if not isinstance(policy.get("reason"), str) or not policy["reason"].strip():
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_REASON")
    if not _sorted_unique_controls(control_universe):
        raise RepairQuarantineError("FAIL_REPAIR_CONTROL_UNIVERSE")

    expected_universe_digest = _sha256(control_universe)
    if policy.get("control_universe_sha256") != expected_universe_digest:
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_UNIVERSE_DIGEST")

    states = policy.get("states")
    if not isinstance(states, list) or not states:
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_STATES")
    by_id: dict[str, Mapping[str, Any]] = {}
    ordered_ids: list[str] = []
    for row in states:
        if not isinstance(row, Mapping) or set(row) != {"control_id", "state", "reentry_evidence"}:
            raise RepairQuarantineError("FAIL_REPAIR_POLICY_STATE_SHAPE")
        cid = row.get("control_id")
        state = row.get("state")
        if not isinstance(cid, str) or CONTROL_ID.fullmatch(cid) is None or cid in by_id:
            raise RepairQuarantineError("FAIL_REPAIR_POLICY_CONTROL_ID")
        if state not in STATES:
            raise RepairQuarantineError(f"FAIL_REPAIR_POLICY_STATE:{cid}")
        if state == "REPAIR_OBSERVE_ONLY":
            if row.get("reentry_evidence") is not None:
                raise RepairQuarantineError(f"FAIL_REPAIR_OBSERVE_WITH_REENTRY:{cid}")
        else:
            _validate_reentry_evidence(row.get("reentry_evidence"))
        ordered_ids.append(cid)
        by_id[cid] = row

    if ordered_ids != sorted(ordered_ids):
        raise RepairQuarantineError("FAIL_REPAIR_POLICY_STATE_ORDER")
    if set(by_id) != set(control_universe):
        missing = sorted(set(control_universe) - set(by_id))
        extra = sorted(set(by_id) - set(control_universe))
        raise RepairQuarantineError(
            "FAIL_REPAIR_POLICY_COVERAGE:"
            f"missing={','.join(missing) or '-'}:extra={','.join(extra) or '-'}"
        )

    contract = policy.get("reentry_contract")
    if not isinstance(contract, Mapping):
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_CONTRACT")
    if contract.get("required") != list(REENTRY_REQUIRED):
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_CONTRACT_REQUIRED")
    if contract.get("one_control_at_a_time") is not True:
        raise RepairQuarantineError("FAIL_REPAIR_REENTRY_ONE_AT_A_TIME")
    if contract.get("silent_reactivation_forbidden") is not True:
        raise RepairQuarantineError("FAIL_REPAIR_SILENT_REACTIVATION")
    return by_id


def project_enforcement(plan: Mapping[str, Any], policy: Mapping[str, Any]) -> dict[str, Any]:
    """Project canonical applicability into temporary enforcement state."""
    if not isinstance(plan, Mapping) or plan.get("schema_version") != PLAN_SCHEMA:
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_SCHEMA")
    if plan.get("coverage_complete") is not True:
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_COVERAGE")

    universe = plan.get("control_universe")
    required = plan.get("required_controls")
    not_applicable = plan.get("not_applicable_controls")
    if not _sorted_unique_controls(universe):
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_UNIVERSE")
    if not _sorted_unique_controls(required):
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_REQUIRED")
    if not set(required).issubset(set(universe)):
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_REQUIRED_OUTSIDE_UNIVERSE")
    if not isinstance(not_applicable, list):
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_NOT_APPLICABLE")
    not_applicable_ids = sorted(
        row.get("control_id")
        for row in not_applicable
        if isinstance(row, Mapping) and isinstance(row.get("control_id"), str)
    )
    if set(required) | set(not_applicable_ids) != set(universe):
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_PARTITION_COVERAGE")
    if set(required) & set(not_applicable_ids):
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_PARTITION_OVERLAP")

    plan_digest = plan.get("plan_sha256")
    if not isinstance(plan_digest, str) or SHA256.fullmatch(plan_digest) is None:
        raise RepairQuarantineError("FAIL_REPAIR_PLAN_DIGEST")

    states = validate_policy(policy, control_universe=list(universe))
    blocking = sorted(cid for cid in required if states[cid]["state"] == "ACTIVE_BLOCKING")
    observe_only = sorted(cid for cid in required if states[cid]["state"] == "REPAIR_OBSERVE_ONLY")
    if set(blocking) | set(observe_only) != set(required) or set(blocking) & set(observe_only):
        raise RepairQuarantineError("FAIL_REPAIR_ENFORCEMENT_PARTITION")

    result: dict[str, Any] = {
        "schema_version": RESULT_SCHEMA,
        "authority": AUTHORITY,
        "policy_id": POLICY_ID,
        "source_plan_sha256": plan_digest,
        "required_controls": list(required),
        "blocking_controls": blocking,
        "observe_only_controls": observe_only,
        "repair_window_active": True,
        "manual_diagnostic_execution_allowed": True,
        "observe_only_results_cannot_block_merge": True,
        "no_applicability_reclassification": True,
        "structural_governance_fail_closed": True,
        "silent_reactivation_forbidden": True,
    }
    result["result_sha256"] = _sha256(result)
    return result


def load_policy(path: Path = POLICY_PATH) -> Mapping[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))
