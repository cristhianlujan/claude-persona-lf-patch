#!/usr/bin/env python3
"""Neutral merge-policy evaluator for the LF PASE.

The upstream Changeset Governance / execution plan owns applicability and routing.
This module only validates a trusted merge-route packet plus already-produced
control or qualification evidence. It does not classify paths, run domain
controls, qualify candidates, mutate GitHub/rulesets, or merge pull requests.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Mapping

INPUT_SCHEMA = "lf-pase-merge-gate-input/v1"
ROUTE_SCHEMA = "lf-pase-merge-route/v1"
PLAN_SCHEMA = "lf-ci-execution-plan/v2"
QUAL_EVIDENCE_SCHEMA = "lf-pase-qualified-evidence/v1"
QUAL_RESULT_SCHEMA = "lf-pase-control-qualification-result/v1"
RESULT_SCHEMA = "lf-pase-merge-gate-result/v1"

ROUTE_AUTHORITY = "CHANGESET_GOVERNANCE_LF_V1"
QUALIFICATION_AUTHORITY = "PASE_CONTROL_QUALIFICATION_V1"
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


def _sorted_unique_control_ids(value: Any) -> bool:
    return (
        isinstance(value, list)
        and all(isinstance(v, str) and CONTROL_ID.fullmatch(v) for v in value)
        and value == sorted(value)
        and len(value) == len(set(value))
    )


def _validate_plan(plan: Mapping[str, Any]) -> list[str]:
    if not isinstance(plan, Mapping) or plan.get("schema_version") != PLAN_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_SCHEMA")
    if plan.get("coverage_complete") is not True:
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_COVERAGE")
    required = plan.get("required_controls")
    if not _sorted_unique_control_ids(required):
        raise PaseMergeGateError("FAIL_PASE_MERGE_PLAN_REQUIRED_CONTROLS")
    return list(required)


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


def _validate_control_results(required: list[str], rows: Any, head_sha: str) -> None:
    if not isinstance(rows, list):
        raise PaseMergeGateError("FAIL_PASE_MERGE_CONTROL_RESULTS")
    by_id: dict[str, Mapping[str, Any]] = {}
    for row in rows:
        if not isinstance(row, Mapping):
            raise PaseMergeGateError("FAIL_PASE_MERGE_CONTROL_RESULT_SHAPE")
        cid = row.get("control_id")
        if not isinstance(cid, str) or CONTROL_ID.fullmatch(cid) is None:
            raise PaseMergeGateError("FAIL_PASE_MERGE_CONTROL_RESULT_ID")
        if cid in by_id:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_DUPLICATE:{cid}")
        if row.get("head_sha") != head_sha:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_HEAD:{cid}")
        if row.get("verdict") != "PASS":
            raise PaseMergeGateError(f"BLOCK_PASE_MERGE_CONTROL_NOT_PASS:{cid}")
        if not isinstance(row.get("authority"), str) or not row["authority"].strip():
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_AUTHORITY:{cid}")
        if not _is_sha256(row.get("evidence_sha256")):
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_CONTROL_RESULT_EVIDENCE:{cid}")
        by_id[cid] = row

    missing = sorted(set(required) - set(by_id))
    extra = sorted(set(by_id) - set(required))
    if missing or extra:
        raise PaseMergeGateError(
            "FAIL_PASE_MERGE_CONTROL_RESULT_COVERAGE:"
            f"missing={','.join(missing) or '-'}:"
            f"extra={','.join(extra) or '-'}"
        )


def _validate_qualification(
    envelope: Any,
    *,
    head_sha: str,
    candidate_id: str,
) -> str:
    if not isinstance(envelope, Mapping) or envelope.get("schema_version") != QUAL_EVIDENCE_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_EVIDENCE_SCHEMA")
    if envelope.get("authority") != QUALIFICATION_AUTHORITY:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_AUTHORITY")
    if envelope.get("independent") is not True or envelope.get("validated") is not True:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_NOT_INDEPENDENT_VALIDATED")
    if not _is_sha256(envelope.get("validator_revision")):
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_VALIDATOR_REVISION")
    if not _is_sha256(envelope.get("result_sha256")):
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_RESULT_DIGEST")

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
    for flag in (
        "activation_authorized",
        "cutover_authorized",
        "rebind_authorized",
        "legacy_retirement_authorized",
    ):
        if result.get(flag) is not False:
            raise PaseMergeGateError(f"FAIL_PASE_MERGE_QUALIFICATION_FORBIDDEN_AUTH:{flag}")

    observed_digest = _sha256(result)
    if observed_digest != envelope["result_sha256"]:
        raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_RESULT_DIGEST_MISMATCH")
    return observed_digest


def evaluate_merge_gate(packet: Mapping[str, Any]) -> dict[str, Any]:
    """Return PASS only when the upstream-selected merge route is fully satisfied."""
    if not isinstance(packet, Mapping) or packet.get("schema_version") != INPUT_SCHEMA:
        raise PaseMergeGateError("FAIL_PASE_MERGE_INPUT_SCHEMA")
    head_sha = packet.get("head_sha")
    if not _is_sha40(head_sha):
        raise PaseMergeGateError("FAIL_PASE_MERGE_HEAD")

    plan = packet.get("plan")
    plan_required = _validate_plan(plan)
    mode, route_required, candidate_id = _validate_route(packet.get("route"), head_sha)

    if not set(route_required).issubset(set(plan_required)):
        raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_CONTROL_OUTSIDE_PLAN")

    qualification = packet.get("qualification")
    if mode == "EXECUTION_PLAN":
        if route_required != plan_required:
            raise PaseMergeGateError("FAIL_PASE_MERGE_ROUTE_PLAN_DRIFT")
        if qualification is not None:
            raise PaseMergeGateError("FAIL_PASE_MERGE_UNEXPECTED_QUALIFICATION")
        qualification_digest = None
    else:
        if qualification is None:
            raise PaseMergeGateError("FAIL_PASE_MERGE_QUALIFICATION_MISSING")
        qualification_digest = _validate_qualification(
            qualification,
            head_sha=head_sha,
            candidate_id=candidate_id or "",
        )

    _validate_control_results(route_required, packet.get("control_results"), head_sha)

    result: dict[str, Any] = {
        "schema_version": RESULT_SCHEMA,
        "producer": "PASE_MERGE_GATE_V1",
        "head_sha": head_sha,
        "route_authority": ROUTE_AUTHORITY,
        "mode": mode,
        "required_control_ids": route_required,
        "qualification_candidate_id": candidate_id,
        "qualification_result_sha256": qualification_digest,
        "verdict": "PASS",
        "merge_ready": True,
        "no_applicability_reclassification": True,
        "no_domain_execution": True,
        "no_candidate_self_qualification": True,
        "no_ruleset_mutation": True,
    }
    result["result_sha256"] = _sha256(result)
    return result
