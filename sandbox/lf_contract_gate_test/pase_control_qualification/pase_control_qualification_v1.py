#!/usr/bin/env python3
"""Independent deterministic validator for PASE_CONTROL_QUALIFICATION_V1 packets.

This module validates qualification evidence/claims. It does not decide Changeset
Governance applicability, execute domain controls, activate candidates, rebind,
cut over, retire legacy, deploy, or mutate live authority.
"""
from __future__ import annotations

import re
from typing import Any, Mapping

INPUT_SCHEMA = "lf-pase-control-qualification/v1"
RESULT_SCHEMA = "lf-pase-control-qualification-result/v1"
TYPES = {"NEW_CONTROL", "CONTROL_REPLACEMENT", "CONTROL_REFACTOR", "OWNER_RUNNER_CHANGE", "BINDING_CHANGE"}
CHECK_IDS = tuple(f"Q{i:02d}" for i in range(1, 12))
CHECK_STATUSES = {"PASS", "FAIL", "BLOCKED", "NA"}
CAUSALITY = {"PROVEN", "DISPROVEN", "UNRESOLVED"}
SHA40 = re.compile(r"^[0-9a-f]{40}$")

class QualificationError(ValueError):
    pass

def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())

def _string_list(value: Any, *, allow_empty: bool = False) -> bool:
    return isinstance(value, list) and (allow_empty or bool(value)) and all(_nonempty(v) for v in value) and len(value) == len(set(value))

def validate_input(packet: Mapping[str, Any]) -> None:
    if not isinstance(packet, Mapping) or packet.get("schema_version") != INPUT_SCHEMA:
        raise QualificationError("FAIL_QUALIFICATION_SCHEMA")
    if packet.get("qualification_type") not in TYPES:
        raise QualificationError("FAIL_QUALIFICATION_TYPE")
    for key in ("repository", "candidate_id", "declared_owner"):
        if not _nonempty(packet.get(key)):
            raise QualificationError(f"FAIL_QUALIFICATION_{key.upper()}")
    for key in ("base_sha", "head_sha", "observed_main_sha"):
        if not isinstance(packet.get(key), str) or not SHA40.fullmatch(packet[key]):
            raise QualificationError(f"FAIL_QUALIFICATION_{key.upper()}")
    if packet["base_sha"] == packet["head_sha"]:
        raise QualificationError("FAIL_QUALIFICATION_EMPTY_CANDIDATE_RANGE")
    for key in ("scope_paths", "owner_local_tests", "boundary_invariants", "expected_coverage"):
        if not _string_list(packet.get(key)):
            raise QualificationError(f"FAIL_QUALIFICATION_{key.upper()}")
    replacement = packet.get("replacement")
    if packet["qualification_type"] == "CONTROL_REPLACEMENT":
        if not isinstance(replacement, Mapping) or not _nonempty(replacement.get("legacy_id")) or replacement.get("replay_required") is not True:
            raise QualificationError("FAIL_QUALIFICATION_REPLACEMENT_REPLAY")

def validate_result(packet: Mapping[str, Any], result: Mapping[str, Any]) -> str:
    validate_input(packet)
    if not isinstance(result, Mapping) or result.get("schema_version") != RESULT_SCHEMA:
        raise QualificationError("FAIL_QUALIFICATION_RESULT_SCHEMA")
    for key in ("candidate_id", "base_sha", "head_sha", "declared_owner"):
        if result.get(key) != packet.get(key):
            raise QualificationError(f"FAIL_QUALIFICATION_IDENTITY_DRIFT:{key}")
    checks = result.get("checks")
    if not isinstance(checks, list) or len(checks) != len(CHECK_IDS):
        raise QualificationError("FAIL_QUALIFICATION_CHECK_SET")
    by_id = {}
    for row in checks:
        if not isinstance(row, Mapping) or row.get("id") not in CHECK_IDS or row.get("id") in by_id or row.get("status") not in CHECK_STATUSES:
            raise QualificationError("FAIL_QUALIFICATION_CHECK_SHAPE")
        evidence = row.get("evidence")
        if not isinstance(evidence, list) or any(not _nonempty(e) for e in evidence):
            raise QualificationError(f"FAIL_QUALIFICATION_EVIDENCE_SHAPE:{row.get('id')}")
        if row["status"] == "PASS" and not evidence:
            raise QualificationError(f"FAIL_QUALIFICATION_PASS_WITHOUT_EVIDENCE:{row['id']}")
        by_id[row["id"]] = row
    if set(by_id) != set(CHECK_IDS):
        raise QualificationError("FAIL_QUALIFICATION_CHECK_COVERAGE")
    if packet["qualification_type"] == "CONTROL_REPLACEMENT" and by_id["Q09"]["status"] == "NA":
        raise QualificationError("FAIL_QUALIFICATION_REPLAY_REQUIRED")

    external = result.get("external_findings")
    if not isinstance(external, list):
        raise QualificationError("FAIL_QUALIFICATION_EXTERNAL_FINDINGS")
    proven_failure = False
    material_unresolved = False
    for finding in external:
        if not isinstance(finding, Mapping) or not _nonempty(finding.get("finding_id")) or finding.get("candidate_causality") not in CAUSALITY:
            raise QualificationError("FAIL_QUALIFICATION_EXTERNAL_FINDING_SHAPE")
        evidence = finding.get("causal_evidence")
        if not isinstance(evidence, list) or any(not _nonempty(e) for e in evidence):
            raise QualificationError("FAIL_QUALIFICATION_CAUSAL_EVIDENCE")
        effect = finding.get("effect_on_candidate_verdict")
        causal = finding["candidate_causality"]
        if causal == "PROVEN":
            if not evidence or effect != "FAIL":
                raise QualificationError("FAIL_QUALIFICATION_PROVEN_CAUSALITY")
            proven_failure = True
        elif causal == "DISPROVEN":
            if effect != "NONE":
                raise QualificationError("FAIL_QUALIFICATION_EXTERNAL_CONTAMINATION")
        else:
            if effect not in {"NONE", "BLOCKED"}:
                raise QualificationError("FAIL_QUALIFICATION_UNRESOLVED_EFFECT")
            material_unresolved |= effect == "BLOCKED"

    for flag in ("qualified_only",):
        if result.get(flag) is not True:
            raise QualificationError(f"FAIL_QUALIFICATION_FLAG:{flag}")
    for flag in ("activation_authorized", "cutover_authorized", "rebind_authorized", "legacy_retirement_authorized"):
        if result.get(flag) is not False:
            raise QualificationError(f"FAIL_QUALIFICATION_FORBIDDEN_AUTHORIZATION:{flag}")

    statuses = {row["status"] for row in checks}
    if proven_failure or "FAIL" in statuses:
        expected = "FAIL"
    elif material_unresolved or "BLOCKED" in statuses:
        expected = "BLOCKED"
    elif result.get("coverage_complete") is True and statuses <= {"PASS", "NA"}:
        expected = "CANDIDATE_QUALIFIED"
    else:
        expected = "BLOCKED"
    if result.get("verdict") != expected:
        raise QualificationError(f"FAIL_QUALIFICATION_VERDICT:expected={expected}:observed={result.get('verdict')}")
    return expected
