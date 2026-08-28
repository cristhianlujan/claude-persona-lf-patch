#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

from trusted_ref_resolver import ResolutionError, TrustedRefResolver

SHA = re.compile(r"^[0-9a-f]{64}$")
PASS_UPSTREAM = {"PASS", "PASS_WITH_RESTRICTIONS", "PASS_EVIDENCE_LINEAGE"}


def good_sha(value):
    return isinstance(value, str) and bool(SHA.fullmatch(value.lower()))


def text(value):
    return isinstance(value, str) and bool(value.strip())


def _resolve(resolver, ref):
    try:
        return resolver.resolve(ref), None
    except ResolutionError as exc:
        return None, exc.code


def _receipt_identity(raw):
    try:
        payload = json.loads(raw.decode("utf-8"))
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    return payload.get("receipt_id") or payload.get("execution_id")


def evaluate(case, resolver=None):
    empty_states = {
        "STRUCTURALLY_VALID": False,
        "PROVENANCE_VALID": False,
        "SEMANTICALLY_VALID": False,
        "ARTIFACT_VERIFIED": False,
        "UPSTREAM_VALID": False,
    }
    if not isinstance(case, dict):
        return {
            "status": "BLOCK_PIPELINE",
            "blocking_codes": ["MALFORMED_CASE"],
            "readback_codes": [],
            "gate_states": empty_states,
        }

    try:
        resolver = resolver or TrustedRefResolver()
    except ResolutionError as exc:
        return {
            "status": "BLOCK_PIPELINE",
            "blocking_codes": [f"TRUSTED_RESOLVER_UNAVAILABLE:{exc.code}"],
            "readback_codes": [],
            "gate_states": empty_states,
        }

    blocking = []
    readback = []
    refs = set()
    receipts = set()
    resolved_authorities = set()
    resolved_sources = {}
    candidate_sha = case.get("candidate_sha")
    provenance_required = case.get("provenance_required", True)
    artifact_required = case.get("artifact_required", True)

    if not text(case.get("claim")):
        blocking.append("CLAIM_MISSING")
    if not good_sha(candidate_sha):
        blocking.append("CANDIDATE_SHA_INVALID")

    sources = case.get("sources")
    if not isinstance(sources, list) or not sources:
        blocking.append("SOURCE_UNIVERSE_MISSING")
        sources = []

    for index, source in enumerate(sources):
        prefix = f"SOURCE_{index}"
        if not isinstance(source, dict):
            blocking.append(prefix + "_MALFORMED")
            continue

        ref = source.get("ref")
        if not text(ref):
            blocking.append(prefix + "_REF_MISSING")
            observed = None
        elif ref in refs:
            blocking.append("DUPLICATE_SOURCE_REF")
            observed = None
        else:
            refs.add(ref)
            observed, resolve_code = _resolve(resolver, ref)
            if observed is None:
                readback.append(prefix + "_REF_UNRESOLVED:" + str(resolve_code))
            else:
                resolved_sources[ref] = observed

        if source.get("required") is True:
            if source.get("read") is not True:
                readback.append(prefix + "_NOT_READ")
            declared_sha = source.get("declared_sha")
            observed_sha = source.get("observed_sha")
            if not good_sha(declared_sha):
                readback.append(prefix + "_DECLARED_SHA_MISSING")
            if not good_sha(observed_sha):
                readback.append(prefix + "_OBSERVED_SHA_MISSING")
            if observed is not None:
                if good_sha(declared_sha) and declared_sha.lower() != observed["sha256"]:
                    readback.append(prefix + "_SHA_MISMATCH")
                if good_sha(observed_sha) and observed_sha.lower() != observed["sha256"]:
                    readback.append(prefix + "_OBSERVED_SHA_NOT_RESOLVER_DERIVED")
                if source.get("current") is not True:
                    readback.append(prefix + "_STALE")
                elif observed.get("current") is not True:
                    readback.append(prefix + "_RESOLVED_REVISION_NOT_CURRENT")
            elif source.get("current") is not True:
                readback.append(prefix + "_STALE")

        if source.get("authority") is True:
            if source.get("derived_from_candidate") is True:
                blocking.append(prefix + "_SELF_CERTIFIED_AUTHORITY")
            elif source.get("relevance") == "MATERIAL" and observed is not None:
                resolved_authorities.add(ref)

        if source.get("role") == "upstream":
            if source.get("validator_status") not in PASS_UPSTREAM:
                blocking.append(prefix + "_UPSTREAM_INVALID")
            if source.get("validator_current") is not True:
                blocking.append(prefix + "_UPSTREAM_VALIDATOR_STALE")

            receipt_id = source.get("receipt_id")
            receipt_ref = source.get("receipt_ref")
            if provenance_required and not text(receipt_id):
                readback.append(prefix + "_RECEIPT_MISSING")
            if provenance_required and not text(receipt_ref):
                readback.append(prefix + "_RECEIPT_REF_MISSING")
            if text(receipt_id):
                if receipt_id in receipts or source.get("receipt_replayed") is True:
                    blocking.append("RECEIPT_REPLAY")
                else:
                    receipts.add(receipt_id)
                if source.get("receipt_subject_sha") != candidate_sha:
                    blocking.append(prefix + "_RECEIPT_SUBJECT_MISMATCH")
            if text(receipt_ref):
                receipt_observed, receipt_code = _resolve(resolver, receipt_ref)
                if receipt_observed is None:
                    readback.append(prefix + "_RECEIPT_REF_UNRESOLVED:" + str(receipt_code))
                elif text(receipt_id):
                    actual_receipt_id = _receipt_identity(receipt_observed["raw"])
                    if actual_receipt_id != receipt_id:
                        blocking.append(prefix + "_RECEIPT_ID_NOT_RESOLVER_VERIFIED")

    if sources and not resolved_authorities:
        blocking.append("INDEPENDENT_AUTHORITY_MISSING")

    if artifact_required:
        artifact_ref = case.get("artifact_ref")
        artifact_sha = case.get("artifact_sha256")
        if case.get("artifact_verified") is not True:
            readback.append("ARTIFACT_NOT_VERIFIED")
        if not text(artifact_ref) or not good_sha(artifact_sha):
            readback.append("ARTIFACT_RESOLVER_BINDING_MISSING")
        else:
            artifact_observed, artifact_code = _resolve(resolver, artifact_ref)
            if artifact_observed is None:
                readback.append("ARTIFACT_REF_UNRESOLVED:" + str(artifact_code))
            else:
                if artifact_sha.lower() != artifact_observed["sha256"]:
                    readback.append("ARTIFACT_SHA_NOT_RESOLVER_DERIVED")
                if artifact_observed.get("current") is not True:
                    readback.append("ARTIFACT_RESOLVED_REVISION_NOT_CURRENT")

    identifiers = case.get("structural_identifiers", [])
    if not isinstance(identifiers, list):
        blocking.append("STRUCTURAL_IDENTIFIERS_MALFORMED")
    else:
        for index, item in enumerate(identifiers):
            if not isinstance(item, dict) or item.get("reconciled") is not True:
                blocking.append(f"STRUCTURAL_IDENTIFIER_{index}_UNRECONCILED")
            elif item.get("observed") != item.get("canonical"):
                blocking.append(f"STRUCTURAL_IDENTIFIER_{index}_MISMATCH")

    conflicts = case.get("conflicts", [])
    if not isinstance(conflicts, list):
        blocking.append("CONFLICTS_MALFORMED")
    else:
        for index, item in enumerate(conflicts):
            if not isinstance(item, dict) or item.get("resolved") is not True:
                blocking.append(f"SOURCE_CONFLICT_{index}_UNRESOLVED")

    assertions = case.get("semantic_assertions")
    if not isinstance(assertions, list) or not assertions:
        blocking.append("INDEPENDENT_SEMANTIC_ASSERTIONS_MISSING")
    else:
        for index, assertion in enumerate(assertions):
            prefix = f"ASSERTION_{index}"
            if not isinstance(assertion, dict):
                blocking.append(prefix + "_MALFORMED")
                continue
            authority_ref = assertion.get("authority_ref")
            if not text(authority_ref):
                blocking.append(prefix + "_AUTHORITY_REF_MISSING")
            elif authority_ref not in resolved_authorities:
                blocking.append(prefix + "_AUTHORITY_REF_NOT_RESOLVED_MATERIAL_AUTHORITY")
            if assertion.get("oracle_id") == case.get("candidate_oracle_id"):
                blocking.append(prefix + "_CORRELATED_ORACLE")
            if assertion.get("derived_from_candidate") is True:
                blocking.append(prefix + "_SELF_DERIVED")
            if assertion.get("match") is not True:
                blocking.append(prefix + "_SEMANTIC_MISMATCH")

    status = "BLOCK_PIPELINE" if blocking else (
        "RETURN_TO_SOURCE_FOR_READBACK" if readback else "PASS_EVIDENCE_LINEAGE"
    )
    provenance_issues = blocking + readback
    return {
        "status": status,
        "blocking_codes": sorted(set(blocking)),
        "readback_codes": sorted(set(readback)),
        "gate_states": {
            "STRUCTURALLY_VALID": not any("MALFORMED" in item or "INVALID" in item for item in blocking),
            "PROVENANCE_VALID": not any(
                "RECEIPT" in item
                or "SHA" in item
                or "_STALE" in item
                or "_NOT_READ" in item
                or "UNRESOLVED" in item
                or "RESOLVER" in item
                for item in provenance_issues
            ),
            "SEMANTICALLY_VALID": not any(
                "ASSERTION" in item
                or "SEMANTIC" in item
                or "CORRELATED" in item
                or "AUTHORITY" in item
                or "CONFLICT" in item
                for item in blocking
            ),
            "ARTIFACT_VERIFIED": not any(item.startswith("ARTIFACT_") for item in readback),
            "UPSTREAM_VALID": not any("UPSTREAM" in item for item in blocking),
        },
    }


def run_matrix(path):
    matrix = json.loads(Path(path).read_text())
    results = []
    failed = False
    for case in matrix.get("cases", []):
        actual = evaluate(case.get("input"))
        code = case.get("expected_code")
        passed = actual["status"] == case.get("expected_status") and (
            code is None or any(code in item for item in actual["blocking_codes"] + actual["readback_codes"])
        )
        failed |= not passed
        results.append({"id": case.get("id"), "kind": case.get("kind"), "actual": actual, "passed": passed})
    digest = hashlib.sha256(json.dumps(results, sort_keys=True).encode()).hexdigest()
    print(json.dumps({"passed": not failed, "case_count": len(results), "results_sha256": digest, "results": results}, indent=2))
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("case", nargs="?")
    parser.add_argument("--matrix")
    args = parser.parse_args()
    if bool(args.case) == bool(args.matrix):
        parser.error("provide exactly one case or --matrix")
    if args.matrix:
        return run_matrix(args.matrix)
    result = evaluate(json.loads(Path(args.case).read_text()))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS_EVIDENCE_LINEAGE" else 1


if __name__ == "__main__":
    sys.exit(main())
