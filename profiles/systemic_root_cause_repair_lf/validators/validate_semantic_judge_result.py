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

def _validate_n1_n2_audit(result: dict, candidate: Any, manifest: Any, trusted_reader: Any = None) -> list[str]:
    """N1/N2 source-value integrity; execution receipt enforced in the existing semantic_judge step."""
    import hashlib
    # Apply by material input contract, not a frozen profile pack version.
    if not isinstance(candidate, dict) or not isinstance(candidate.get("current_uncertainties"), list):
        return []
    required = {}
    errors = []
    for item in candidate.get("current_uncertainties") or []:
        if not isinstance(item, dict) or item.get("impact") != "DESIGN_BLOCKING":
            continue
        c = item.get("cascade")
        if not isinstance(c, dict) or "catalog_queries" not in c:
            errors.append("N1_N2_REQUIRED_QUERIES_MISSING")
            continue
        uid = item.get("uncertainty_id")
        if not isinstance(uid, str) or not uid:
            errors.append("N1_N2_DATUM_ID_MISSING")
            continue
        for q in c.get("catalog_queries") or []:
            if not isinstance(q, dict) or q.get("level") not in ("N1", "N2"):
                continue
            key = (uid, q["level"])
            if key in required:
                errors.append("N1_N2_QUERY_DUPLICATE")
            required[key] = q
    if any({lv for (id_, lv) in required if id_ == item.get("uncertainty_id")} != {"N1", "N2"} for item in (candidate.get("current_uncertainties") or []) if isinstance(item, dict) and item.get("impact") == "DESIGN_BLOCKING"):
        errors.append("N1_N2_QUALITY_LEVEL_MISSING")
    if not required:
        return errors
    observations = result.get("n1_n2_audit")
    if not isinstance(observations, list):
        return errors + ["N1_N2_AUDIT_MISSING"]
    proofs = {x.get("evidence_id"): x for x in (manifest or {}).get("evidence", [])
              if isinstance(x, dict) and x.get("state") == "CURRENT"} if isinstance(manifest, dict) else {}
    seen = set()
    for a in observations:
        if not isinstance(a, dict):
            errors.append("N1_N2_AUDIT_INVALID")
            continue
        key = (a.get("datum_id"), a.get("level"))
        if key in seen or key not in required:
            errors.append("N1_N2_AUDIT_DUPLICATE_OR_UNEXPECTED")
            continue
        seen.add(key)
        q = required[key]
        data, eid = q.get("readback"), q.get("evidence_id")
        proof = proofs.get(eid)
        if not isinstance(data, dict) or not proof:
            errors.append("N1_N2_SOURCE_PROOF_MISSING")
            continue
        digest = "sha256:" + hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
        # A producer-supplied locator is not independently executed evidence.
        # The existing trusted caller must supply a real source-reader callback.
        if not callable(trusted_reader):
            errors.append("N1_N2_TRUSTED_READER_NOT_WIRED")
        else:
            try:
                observed = trusted_reader(eid, data.get("query"), key[0], key[1])
            except Exception:
                observed = None
            if not isinstance(observed, dict) or any((
                observed.get("verified") is not True,
                observed.get("source_locator") != data.get("query"),
                observed.get("source_digest") != digest,
                observed.get("datum_id") != key[0],
                observed.get("level") != key[1],
                observed.get("candidate_sha256") != result.get("candidate_sha256"),
                observed.get("independent_source_ref") != a.get("independent_source_ref"),
                observed.get("row_count") != data.get("row_count"),
                observed.get("sample_records") != data.get("sample_records"),
            )):
                errors.append("N1_N2_INDEPENDENT_READBACK_NOT_PROVEN")
        if proof.get("digest") != digest or proof.get("source_locator") != data.get("query"):
            errors.append("N1_N2_SOURCE_DIGEST_MISMATCH")
        if a.get("evidence_id") != eid or a.get("source_locator") != data.get("query"):
            errors.append("N1_N2_AUDIT_PROVENANCE_MISMATCH")
        if any(a.get(k) != data.get(k) for k in ("result_kind", "row_count", "sample_records")):
            errors.append("N1_N2_AUDIT_VALUE_MISMATCH")
        if a.get("comparison") != "MATCH" or not a.get("independent_source_ref") or not a.get("independent_observed_at"):
            errors.append("N1_N2_INDEPENDENT_READBACK_NOT_PROVEN")
    if seen != set(required):
        errors.append("N1_N2_AUDIT_INCOMPLETE")
    if result.get("verdict") == PASS_VERDICT and result.get("n1_n2_verdict") != "PASS":
        errors.append("N1_N2_PASS_NOT_ISSUED")
    return errors

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


def evaluate(payload: Any, scope_packet: Any = None, expected_candidate_sha256: str | None = None, expected_scope_packet_sha256: str | None = None, candidate: Any = None, evidence_manifest: Any = None, trusted_reader: Any = None) -> dict[str, Any]:
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

    errors.extend(_validate_n1_n2_audit(payload, candidate, evidence_manifest, trusted_reader))
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
