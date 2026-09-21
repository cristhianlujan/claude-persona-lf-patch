#!/usr/bin/env python3
"""Deterministic shape/coverage floor for SRCR Independent Semantic Judge B.

This validator does NOT extract candidate changes and does NOT decide semantic scope.
It only verifies that an already-executed semantic judge accounted for all supplied
scope items and all independently observed changes, and that PASS is internally
consistent with the judge's own findings.
"""

from __future__ import annotations

import json
import sys
from typing import Any

REQUIRED_INVARIANTS = {
    "SCOPE_AUTHORITY_INTEGRITY",
    "EVIDENCE_INTEGRITY",
    "CAUSAL_CLOSURE",
    "CONTRADICTION_INTEGRITY",
    "MINIMUM_SUFFICIENT_REUSE",
    "INDEPENDENT_DECISION_CLOSURE",
    "FALSIFIABILITY_REGRESSION",
}
PASS_VERDICT = "PASS_INDEPENDENT_SEMANTIC"
FAIL_VERDICTS = {
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE",
}
SHA_LEN = 64


def _ids(items: Any, key: str) -> list[str]:
    if not isinstance(items, list):
        return []
    return [
        str(item.get(key))
        for item in items
        if isinstance(item, dict) and isinstance(item.get(key), str) and item.get(key)
    ]


def _sha_ok(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != SHA_LEN:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def _scope_ids(scope_packet: Any) -> set[str]:
    if not isinstance(scope_packet, dict):
        return set()
    out: set[str] = set()
    for key in ("authorized_requirements", "constraints", "forbidden_changes"):
        rows = scope_packet.get(key)
        if isinstance(rows, list):
            for row in rows:
                if isinstance(row, dict) and isinstance(row.get("id"), str) and row.get("id"):
                    out.add(row["id"])
    return out


def evaluate(payload: Any, scope_packet: Any = None, expected_candidate_sha256: str | None = None, expected_scope_packet_sha256: str | None = None) -> dict[str, Any]:
    errors: list[str] = []
    if not isinstance(payload, dict):
        return {"status": "FAIL", "blocking_codes": ["SEMANTIC_JUDGE_RESULT_NOT_OBJECT"]}

    verdict = payload.get("verdict")
    if verdict not in ({PASS_VERDICT} | FAIL_VERDICTS):
        errors.append("SEMANTIC_JUDGE_VERDICT_INVALID")

    if not _sha_ok(payload.get("candidate_sha256")):
        errors.append("SEMANTIC_JUDGE_CANDIDATE_SHA_INVALID")
    if not _sha_ok(payload.get("scope_packet_sha256")):
        errors.append("SEMANTIC_JUDGE_SCOPE_SHA_INVALID")
    if expected_candidate_sha256 is not None and payload.get("candidate_sha256") != expected_candidate_sha256:
        errors.append("SEMANTIC_JUDGE_CANDIDATE_SHA_MISMATCH")
    if expected_scope_packet_sha256 is not None and payload.get("scope_packet_sha256") != expected_scope_packet_sha256:
        errors.append("SEMANTIC_JUDGE_SCOPE_SHA_MISMATCH")

    observed = payload.get("observed_candidate_changes")
    if not isinstance(observed, list):
        errors.append("OBSERVED_CANDIDATE_CHANGES_MISSING")
        observed = []
    observed_ids = _ids(observed, "change_id")
    if len(observed_ids) != len(set(observed_ids)):
        errors.append("OBSERVED_CANDIDATE_CHANGE_ID_DUPLICATE")

    requirement = payload.get("requirement_reconciliation")
    if not isinstance(requirement, list):
        errors.append("REQUIREMENT_RECONCILIATION_MISSING")
        requirement = []
    for item in requirement:
        if not isinstance(item, dict) or not item.get("scope_item_id") or item.get("disposition") not in {
            "SATISFIED", "PRESERVED", "NOT_APPLICABLE_WITH_EVIDENCE", "VIOLATED", "UNRESOLVED"
        }:
            errors.append("REQUIREMENT_RECONCILIATION_INVALID")
            break
    if scope_packet is not None:
        expected_scope_ids = _scope_ids(scope_packet)
        observed_scope_ids = set(_ids(requirement, "scope_item_id"))
        if expected_scope_ids != observed_scope_ids:
            errors.append("REQUIREMENT_SCOPE_COVERAGE_INCOMPLETE")

    declaration = payload.get("change_declaration_reconciliation")
    if not isinstance(declaration, list):
        errors.append("CHANGE_DECLARATION_RECONCILIATION_MISSING")
        declaration = []
    declared_change_ids = _ids(declaration, "change_id")

    conformance = payload.get("scope_conformance_reconciliation")
    if not isinstance(conformance, list):
        errors.append("SCOPE_CONFORMANCE_RECONCILIATION_MISSING")
        conformance = []
    scoped_change_ids = _ids(conformance, "change_id")

    if set(observed_ids) != set(declared_change_ids):
        errors.append("OBSERVED_CHANGE_DECLARATION_COVERAGE_INCOMPLETE")
    if set(observed_ids) != set(scoped_change_ids):
        errors.append("OBSERVED_CHANGE_SCOPE_COVERAGE_INCOMPLETE")

    invariants = payload.get("invariant_results")
    if not isinstance(invariants, list):
        errors.append("INVARIANT_RESULTS_MISSING")
        invariants = []
    seen_invariants = {
        item.get("invariant")
        for item in invariants
        if isinstance(item, dict) and item.get("result") in {"PASS", "FAIL", "BLOCKED"}
    }
    if REQUIRED_INVARIANTS - seen_invariants:
        errors.append("INVARIANT_COVERAGE_INCOMPLETE")

    blocking = payload.get("blocking_codes")
    if not isinstance(blocking, list):
        errors.append("SEMANTIC_JUDGE_BLOCKING_CODES_INVALID")
        blocking = []

    if verdict == PASS_VERDICT:
        if blocking:
            errors.append("SEMANTIC_PASS_WITH_BLOCKING_CODES")
        if any(isinstance(x, dict) and x.get("result") != "PASS" for x in invariants):
            errors.append("SEMANTIC_PASS_WITH_FAILED_INVARIANT")
        if any(isinstance(x, dict) and x.get("disposition") in {"VIOLATED", "UNRESOLVED"} for x in requirement):
            errors.append("SEMANTIC_PASS_WITH_REQUIREMENT_GAP")
        if any(isinstance(x, dict) and x.get("disposition") == "UNDECLARED_PROPOSED_CHANGE" for x in declaration):
            errors.append("SEMANTIC_PASS_WITH_UNDECLARED_CHANGE")
        if any(isinstance(x, dict) and x.get("disposition") in {"OUT_OF_SCOPE_DESIGN_DELTA", "UNRESOLVED_SCOPE"} for x in conformance):
            errors.append("SEMANTIC_PASS_WITH_SCOPE_VIOLATION")
        if payload.get("open_design_decisions_found"):
            errors.append("SEMANTIC_PASS_WITH_OPEN_DESIGN_DECISIONS")

    return {
        "status": "PASS" if not errors else "FAIL",
        "blocking_codes": sorted(set(errors)),
    }


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("result")
    parser.add_argument("--scope-packet")
    parser.add_argument("--candidate-sha256")
    parser.add_argument("--scope-packet-sha256")
    args = parser.parse_args()
    with open(args.result, "r", encoding="utf-8") as fh:
        payload = json.load(fh)
    scope_packet = None
    if args.scope_packet:
        with open(args.scope_packet, "r", encoding="utf-8") as fh:
            scope_packet = json.load(fh)
    result = evaluate(
        payload,
        scope_packet=scope_packet,
        expected_candidate_sha256=args.candidate_sha256,
        expected_scope_packet_sha256=args.scope_packet_sha256,
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
