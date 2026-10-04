#!/usr/bin/env python3
"""Neutral LF PASE merge-policy evaluator.

Applicability is owned upstream. During the repair window, only ACTIVE_BLOCKING
controls may block merge. A dispatch receipt authorizes handoff/entry; it is never
terminal execution evidence. Blocking controls require a VERIFIED typed terminal
verdict anchored in the existing Evidence Ledger.
"""
from __future__ import annotations

import hashlib
import json
import re
import uuid
from typing import Any, Mapping

INPUT_SCHEMA = "lf-pase-merge-gate-input/v1"
ROUTE_SCHEMA = "lf-pase-merge-route/v1"
PLAN_SCHEMA = "lf-ci-execution-plan/v2"
ENFORCEMENT_SCHEMA = "lf-pase-control-enforcement/v1"
QUAL_EVIDENCE_SCHEMA = "lf-pase-qualified-evidence/v1"
QUAL_RESULT_SCHEMA = "lf-pase-control-qualification-result/v1"
TERMINAL_VERDICT_SCHEMA = "lf-pase-control-terminal-verdict/v1"
RESULT_SCHEMA = "lf-pase-merge-gate-result/v1"

ROUTE_AUTHORITY = "CHANGESET_GOVERNANCE_LF_V1"
ENFORCEMENT_AUTHORITY = "CHANGESET_GOVERNANCE_LF_V1"
REPAIR_POLICY_ID = "PASE_CONTROL_REPAIR_QUARANTINE_V1"
QUALIFICATION_AUTHORITY = "PASE_CONTROL_QUALIFICATION_V1"
TERMINAL_VERDICT_AUTHORITY = "EVIDENCE_LEDGER"
TERMINAL_RECEIPT_KIND = "CONTROL_TERMINAL_VERDICT"
MODES = {"EXECUTION_PLAN", "CONTROL_SYSTEM_QUALIFICATION"}
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
CONTROL_ID = re.compile(r"^[A-Z][A-Z0-9_]*$")


class PaseMergeGateError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _is_sha40(value: Any) -> bool:
    return isinstance(value, str) and SHA40.fullmatch(value) is not None


def _is_sha256(value: Any) -> bool:
    return isinstance(value, str) and SHA256.fullmatch(value) is not None


def _is_uuid(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        uuid.UUID(value)
        return True
    except (ValueError, AttributeError):
        return False


def _sorted_unique_control_ids(value: Any) -> bool:
    return (
        isinstance(value, list)
        and all(isinstance(v, str) and CONTROL_ID.fullmatch(v) for v in value)
        and value == sorted(value)
        and len(value) == len(set(value))
    )


def _validate_plan(plan: Mapping[str, Any]) -> tuple[list[str], str]:
    if not isinstance(plan, Mapping) or plan.get("schema_version") != PLAN_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_SCHEMA")
    if plan.get("coverage_complete") is not True:
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_COVERAGE")
    required = plan.get("required_controls")
    if not _sorted_unique_control_ids(required):
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_REQUIRED_CONTROLS")
    digest = plan.get("plan_sha256")
    if not _is_sha256(digest):
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_DIGEST")
    return list(required), digest


def _validate_enforcement(enforcement: Any, plan_required: list[str], plan_digest: str) -> tuple[list[str], list[str]]:
    if not isinstance(enforcement, Mapping) or enforcement.get("schema_version") != ENFORCEMENT_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_SCHEMA")
    if enforcement.get("authority") != ENFORCEMENT_AUTHORITY or enforcement.get("policy_id") != REPAIR_POLICY_ID:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_AUTHORITY")
    if enforcement.get("source_plan_sha256") != plan_digest:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_PLAN_DRIFT")
    if enforcement.get("required_controls") != plan_required:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_REQUIRED_DRIFT")
    blocking = enforcement.get("blocking_controls")
    observe = enforcement.get("observe_only_controls")
    if not _sorted_unique_control_ids(blocking) or not _sorted_unique_control_ids(observe):
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_CONTROL_SET")
    if set(blocking) & set(observe) or set(blocking) | set(observe) != set(plan_required):
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_PARTITION")
    for flag in (
        "repair_window_active",
        "observe_only_results_cannot_block_merge",
        "no_applicability_reclassification",
        "structural_governance_fail_closed",
        "silent_reactivation_forbidden",
    ):
        if enforcement.get(flag) is not True:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_ENFORCEMENT_FLAG:{flag}")
    observed = dict(enforcement)
    claimed = observed.pop("result_sha256", None)
    if not _is_sha256(claimed) or _sha256(observed) != claimed:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ENFORCEMENT_DIGEST")
    return list(blocking), list(observe)


def _validate_route(route: Mapping[str, Any], head_sha: str) -> tuple[str, list[str], str | None]:
    if not isinstance(route, Mapping) or route.get("schema_version") != ROUTE_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_SCHEMA")
    if route.get("authority") != ROUTE_AUTHORITY:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_AUTHORITY")
    mode = route.get("mode")
    if mode not in MODES:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_MODE")
    if route.get("head_sha") != head_sha:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_HEAD_DRIFT")
    if not _is_sha256(route.get("source_revision")):
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_SOURCE_REVISION")
    required = route.get("required_control_ids")
    if not _sorted_unique_control_ids(required):
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_REQUIRED_CONTROLS")
    candidate_id = route.get("candidate_id")
    if mode == "CONTROL_SYSTEM_QUALIFICATION":
        if not isinstance(candidate_id, str) or not candidate_id.strip():
            raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_CANDIDATE")
    elif candidate_id is not None:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_UNEXPECTED_CANDIDATE")
    return mode, list(required), candidate_id


def _validate_terminal_verdict(row: Mapping[str, Any], *, control_id: str, head_sha: str, plan_digest: str) -> str:
    """Validate one terminal verdict projection from canonical Evidence Ledger data."""
    if row.get("schema_version") != TERMINAL_VERDICT_SCHEMA:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_SCHEMA:{control_id}")
    if row.get("control_id") != control_id:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_CONTROL:{control_id}")
    capability_code = row.get("capability_code")
    if not isinstance(capability_code, str) or CONTROL_ID.fullmatch(capability_code) is None:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_CAPABILITY:{control_id}")
    if row.get("authority") != TERMINAL_VERDICT_AUTHORITY:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_AUTHORITY:{control_id}")
    if row.get("receipt_kind") != TERMINAL_RECEIPT_KIND or row.get("verification_state") != "VERIFIED":
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_LEDGER_STATE:{control_id}")
    if row.get("plan_digest") != plan_digest:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_PLAN:{control_id}")
    if row.get("head_sha") != head_sha or row.get("source_head_sha") != head_sha:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_HEAD:{control_id}")
    execution_id = row.get("execution_id")
    runner_execution_id = row.get("runner_execution_id")
    orchestrator_execution_id = row.get("orchestrator_execution_id")
    if not isinstance(execution_id, str) or not execution_id.strip():
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_EXECUTION:{control_id}")
    if runner_execution_id != execution_id:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_RUNNER:{control_id}")
    if not isinstance(orchestrator_execution_id, str) or not orchestrator_execution_id.strip():
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_ORCHESTRATOR:{control_id}")
    dispatch_receipt_id = row.get("dispatch_receipt_id")
    evidence_receipt_id = row.get("evidence_ledger_receipt_id")
    if not _is_uuid(dispatch_receipt_id):
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_DISPATCH_RECEIPT:{control_id}")
    if not _is_uuid(evidence_receipt_id):
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_EVIDENCE_RECEIPT:{control_id}")
    if dispatch_receipt_id == evidence_receipt_id:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_DISPATCH_IS_TERMINAL_VERDICT:{control_id}")
    for field in ("dispatch_receipt_sha256", "receipt_sha256", "evidence_sha256"):
        if not _is_sha256(row.get(field)):
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_DIGEST:{control_id}:{field}")
    if row.get("actual_runner_execution") is not True or row.get("terminal") is not True:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_EXECUTION_PROOF:{control_id}")
    if row.get("dispatch_only") is not False:
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_TERMINAL_VERDICT_DISPATCH_ONLY:{control_id}")
    verdict = row.get("verdict")
    if verdict != "PASS":
        raise PaseMergeGateError(f"BLOCK_PASE_MERGE_CONTROL_NOT_PASS:{control_id}")
    return str(evidence_receipt_id)


def _validate_control_results(required: list[str], rows: Any, head_sha: str, plan_digest: str) -> dict[str, str]:
    if not isinstance(rows, list):
        raise PaseMergeGateError("FAIL_PASE_MERGE_CONTROL_RESULTS")
    by_id: dict[str, Mapping[str, Any]] = {}
    receipt_ids: dict[str, str] = {}
    for row in rows:
        if not isinstance(row, Mapping):
            raise PaseMergeGateError("FAIL_PASE_MERGE_CONTROL_RESULT_SHAPE")
        cid = row.get("control_id")
        if not isinstance(cid, str) or CONTROL_ID.fullmatch(cid) is None:
            raise PaseMergeGateError("FAIL_PASE_MERGE_CONTROL_RESULT_ID")
        if cid in by_id:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_DUPLICATE:{cid}")
        if cid not in required:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_UNPLANNED:{cid}")
        receipt_ids[cid] = _validate_terminal_verdict(row, control_id=cid, head_sha=head_sha, plan_digest=plan_digest)
        by_id[cid] = row
    if set(by_id) != set(required):
        missing = sorted(set(required) - set(by_id))
        extra = sorted(set(by_id) - set(required))
        raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE:missing={','.join(missing) or '-'}:extra={','.join(extra) or '-'}")
    return receipt_ids


def _validate_diagnostics(observe_only: list[str], rows: Any, head_sha: str) -> None:
    if rows is None:
        return
    if not isinstance(rows, list):
        raise PaseMergeGateError("FAIL_PASE_MERGE_DIAGNOSTIC_RESULTS")
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, Mapping):
            raise PaseMergeGateError("FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_SHAPE")
        cid = row.get("control_id")
        if cid not in observe_only or cid in seen:
            raise PaseMergeGateError("FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_CONTROL")
        if row.get("head_sha") != head_sha:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_HEAD:{cid}")
        if not isinstance(row.get("verdict"), str) or not row["verdict"].strip():
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_DIAGNOSTIC_RESULT_VERDICT:{cid}")
        seen.add(cid)


def _validate_qualification(envelope: Any, *, head_sha: str, candidate_id: str) -> str:
    if not isinstance(envelope, Mapping) or envelope.get("schema_version") != QUAL_EVIDENCE_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_EVIDENCE_SCHEMA")
    if envelope.get("authority") != QUALIFICATION_AUTHORITY:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_AUTHORITY")
    if envelope.get("independent") is not True or envelope.get("validated") is not True:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_NOT_INDEPENDENT_VALIDATED")
    if not _is_sha256(envelope.get("validator_revision")) or not _is_sha256(envelope.get("result_sha256")):
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_DIGEST")
    result = envelope.get("result")
    if not isinstance(result, Mapping) or result.get("schema_version") != QUAL_RESULT_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_RESULT_SCHEMA")
    if result.get("candidate_id") != candidate_id:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_CANDIDATE_DRIFT")
    if result.get("head_sha") != head_sha:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_HEAD_DRIFT")
    if result.get("verdict") != "CANDIDATE_QUALIFIED":
        raise PaseMergeGateError("BLOCK_PASE_MERGE_QUALIFICATION_NOT_QUALIFIED")
    if result.get("qualified_only") is not True:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_FLAG")
    for flag in ("activation_authorized", "cutover_authorized", "rebind_authorized", "legacy_retirement_authorized"):
        if result.get(flag) is not False:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_QUALIFICATION_FORBIDDEN_AUTH:{flag}")
    observed = _sha256(result)
    if observed != envelope["result_sha256"]:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_RESULT_DIGEST_MISMATCH")
    return observed


def evaluate_merge_gate(packet: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(packet, Mapping) or packet.get("schema_version") != INPUT_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_INPUT_SCHEMA")
    head_sha = packet.get("head_sha")
    if not _is_sha40(head_sha):
        raise PaseMergeGateError("FAIL_PASE_MERGE_HEAD")

    plan_required, plan_digest = _validate_plan(packet.get("plan"))
    blocking, observe_only = _validate_enforcement(packet.get("enforcement"), plan_required, plan_digest)
    mode, route_required, candidate_id = _validate_route(packet.get("route"), head_sha)
    if route_required != blocking:
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_ENFORCEMENT_DRIFT")

    qualification = packet.get("qualification")
    if mode == "CONTROL_SYSTEM_QUALIFICATION":
        if qualification is None:
            raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_MISSING")
        qualification_digest = _validate_qualification(qualification, head_sha=head_sha, candidate_id=candidate_id or "")
    else:
        if qualification is not None:
            raise PaseMergeGateError("FAIL_PASE_MERGE_UNEXPECTED_QUALIFICATION")
        qualification_digest = None

    terminal_receipts = _validate_control_results(blocking, packet.get("control_results"), head_sha, plan_digest)
    _validate_diagnostics(observe_only, packet.get("diagnostic_results"), head_sha)

    result: dict[str, Any] = {
        "schema_version": RESULT_SCHEMA,
        "producer": "PASE_MERGE_GATE_V1",
        "head_sha": head_sha,
        "route_authority": ROUTE_AUTHORITY,
        "repair_policy_id": REPAIR_POLICY_ID,
        "mode": mode,
        "applicable_control_ids": plan_required,
        "required_control_ids": blocking,
        "observe_only_control_ids": observe_only,
        "terminal_verdict_authority": TERMINAL_VERDICT_AUTHORITY,
        "terminal_verdict_receipt_ids": terminal_receipts,
        "dispatch_receipt_is_terminal_verdict": False,
        "qualification_candidate_id": candidate_id,
        "qualification_result_sha256": qualification_digest,
        "verdict": "PASS",
        "merge_ready": True,
        "no_applicability_reclassification": True,
        "observe_only_results_cannot_block_merge": True,
        "no_domain_execution": True,
        "no_candidate_self_qualification": True,
        "no_ruleset_mutation": True,
    }
    result["result_sha256"] = _sha256(result)
    return result
