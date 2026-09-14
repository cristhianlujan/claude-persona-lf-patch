#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / "LF_CI_EVIDENCE_CONTRACT_V1.json").read_text(encoding="utf-8"))
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

PURPOSE_PROFILE = {
    "PRE_MERGE_CANDIDATE_VALIDATION": "PRE_MERGE_STANDARD",
    "PRE_MERGE_WITH_CURRENTNESS": "PRE_MERGE_WITH_CURRENTNESS",
    "POST_MERGE_ARTIFACT_RECONCILIATION": "POST_MERGE_ARTIFACT_RECONCILIATION",
}


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def finalize_receipt(receipt: dict[str, Any]) -> dict[str, Any]:
    out = dict(receipt)
    out.pop("receipt_sha256", None)
    out["receipt_sha256"] = canonical_sha256(out)
    return out


def receipt_hash_valid(receipt: dict[str, Any]) -> bool:
    supplied = receipt.get("receipt_sha256")
    unsigned = dict(receipt)
    unsigned.pop("receipt_sha256", None)
    return isinstance(supplied, str) and HEX64.fullmatch(supplied) is not None and canonical_sha256(unsigned) == supplied


def _basic_request_findings(request: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    if request.get("request_version") != "LF_CI_EVIDENCE_REQUEST_V1":
        findings.append("REQUEST_VERSION_INVALID")
    repo = request.get("repository_full_name")
    if not isinstance(repo, str) or REPO.fullmatch(repo) is None:
        findings.append("REPOSITORY_IDENTITY_INVALID")
    for field in ("candidate_head_sha", "base_sha"):
        value = request.get(field)
        if not isinstance(value, str) or HEX40.fullmatch(value) is None:
            findings.append(field.upper() + "_INVALID")
    if not isinstance(request.get("target_branch"), str) or not request.get("target_branch", "").strip():
        findings.append("TARGET_BRANCH_INVALID")
    pr = request.get("pr_number")
    if pr is not None and (not isinstance(pr, int) or isinstance(pr, bool) or pr < 1):
        findings.append("PR_NUMBER_INVALID")
    purpose = request.get("evidence_purpose")
    profile = request.get("requirement_profile")
    if purpose not in PURPOSE_PROFILE or PURPOSE_PROFILE.get(purpose) != profile:
        findings.append("PURPOSE_PROFILE_MISMATCH")
    if not isinstance(request.get("provider_receipts"), list):
        findings.append("PROVIDER_RECEIPTS_INVALID")
    return findings


def _subject_mismatch(request: dict[str, Any], receipt: dict[str, Any]) -> list[str]:
    fields = ("repository_full_name", "candidate_head_sha", "base_sha", "target_branch", "pr_number")
    return [field for field in fields if receipt.get(field) != request.get(field)]


def _provider_envelope_bad(receipt: dict[str, Any]) -> list[str]:
    bad: list[str] = []
    if receipt.get("receipt_version") != "LF_CI_PROVIDER_RECEIPT_V1":
        bad.append("RECEIPT_VERSION")
    if not isinstance(receipt.get("source_ref"), str) or not receipt.get("source_ref", "").strip():
        bad.append("SOURCE_REF")
    if not isinstance(receipt.get("observed_at"), str) or not receipt.get("observed_at", "").strip():
        bad.append("OBSERVED_AT")
    if not receipt_hash_valid(receipt):
        bad.append("RECEIPT_HASH")
    return bad


def _workflow_common(receipt: dict[str, Any], spec: dict[str, Any]) -> list[str]:
    bad: list[str] = []
    if receipt.get("workflow_name") != spec.get("workflow_name"):
        bad.append("WORKFLOW_NAME")
    if receipt.get("workflow_path") != spec.get("workflow_path"):
        bad.append("WORKFLOW_PATH")
    if receipt.get("event") != "pull_request":
        bad.append("WORKFLOW_EVENT")
    if receipt.get("conclusion") != "success":
        bad.append("WORKFLOW_CONCLUSION")
    if not isinstance(receipt.get("run_id"), int) or isinstance(receipt.get("run_id"), bool) or receipt.get("run_id", 0) < 1:
        bad.append("RUN_ID")
    if not isinstance(receipt.get("run_attempt"), int) or isinstance(receipt.get("run_attempt"), bool) or receipt.get("run_attempt", 0) < 1:
        bad.append("RUN_ATTEMPT")
    return bad


def _validate_contract_deep(receipt: dict[str, Any], spec: dict[str, Any]) -> list[str]:
    bad = _workflow_common(receipt, spec)
    if receipt.get("provider_mode") != "DEEP_RUN":
        bad.append("DEEP_MODE")
    if receipt.get("deep_job_name") != spec.get("deep_job_name"):
        bad.append("DEEP_JOB_NAME")
    if receipt.get("deep_job_conclusion") != "success":
        bad.append("DEEP_JOB_CONCLUSION")
    if not isinstance(receipt.get("deep_job_id"), int) or isinstance(receipt.get("deep_job_id"), bool) or receipt.get("deep_job_id", 0) < 1:
        bad.append("DEEP_JOB_ID")
    artifact = receipt.get("audit_artifact")
    if not isinstance(artifact, dict):
        return bad + ["AUDIT_ARTIFACT_MISSING"]
    expected_name = str(spec.get("audit_artifact_name_pattern", "")).format(run_id=receipt.get("run_id"))
    if artifact.get("name") != expected_name:
        bad.append("AUDIT_ARTIFACT_NAME")
    if not isinstance(artifact.get("id"), int) or isinstance(artifact.get("id"), bool) or artifact.get("id", 0) < 1:
        bad.append("AUDIT_ARTIFACT_ID")
    if artifact.get("expired") is not False:
        bad.append("AUDIT_ARTIFACT_EXPIRED")
    if artifact.get("head_sha") != receipt.get("candidate_head_sha"):
        bad.append("AUDIT_ARTIFACT_HEAD")
    if not isinstance(artifact.get("digest"), str) or ARTIFACT_DIGEST.fullmatch(artifact.get("digest", "")) is None:
        bad.append("AUDIT_ARTIFACT_DIGEST")
    return bad


def _validate_currentness(request: dict[str, Any], receipt: dict[str, Any]) -> list[str]:
    bad: list[str] = []
    if receipt.get("provider_mode") != "OFFLINE_SOURCE_ATTESTATION":
        bad.append("CURRENTNESS_MODE")
    att = receipt.get("attestation_receipt")
    if not isinstance(att, dict):
        return bad + ["ATTESTATION_MISSING"]
    if not receipt_hash_valid(att):
        bad.append("ATTESTATION_HASH")
    if att.get("schema_version") != "LF_SOURCE_ATTESTATION_RECEIPT_V1":
        bad.append("ATTESTATION_SCHEMA")
    if att.get("repo_identity") != f"github://{request.get('repository_full_name')}":
        bad.append("ATTESTATION_REPOSITORY")
    if att.get("authority_ref") != f"refs/heads/{request.get('target_branch')}":
        bad.append("ATTESTATION_AUTHORITY_REF")
    if att.get("resolved_revision") != request.get("base_sha") or att.get("commit_sha") != request.get("base_sha"):
        bad.append("ATTESTATION_BASE_REVISION")
    if att.get("authority_level") != "CANDIDATE_LOCAL_INTEGRITY" or att.get("durable_evidence_anchor_required") is not True:
        bad.append("ATTESTATION_AUTHORITY_LEVEL")
    if att.get("network_required_for_verification") is not False:
        bad.append("ATTESTATION_OFFLINE_REUSE")
    return bad


def _validate_post_merge(request: dict[str, Any], receipt: dict[str, Any]) -> list[str]:
    bad: list[str] = []
    if receipt.get("provider_mode") != "V7_AUTHORITATIVE_POST_MERGE":
        bad.append("RECONCILIATION_MODE")
    if receipt.get("authoritative") is not True:
        bad.append("RECONCILIATION_AUTHORITY")
    if receipt.get("merge_commit_sha") != request.get("candidate_head_sha"):
        bad.append("RECONCILIATION_MERGE_SHA")
    if not isinstance(receipt.get("reconciliation_run_id"), int) or isinstance(receipt.get("reconciliation_run_id"), bool) or receipt.get("reconciliation_run_id", 0) < 1:
        bad.append("RECONCILIATION_RUN_ID")
    if not isinstance(receipt.get("verification_payload_sha256"), str) or HEX64.fullmatch(receipt.get("verification_payload_sha256", "")) is None:
        bad.append("RECONCILIATION_PAYLOAD_HASH")
    return bad


def aggregate(request: dict[str, Any]) -> dict[str, Any]:
    request_findings = _basic_request_findings(request)
    findings = list(request_findings)
    profile = request.get("requirement_profile")
    profile_spec = (CONTRACT.get("requirement_profiles") or {}).get(profile) or {}
    required = list(profile_spec.get("required_providers") or [])
    receipts = request.get("provider_receipts") if isinstance(request.get("provider_receipts"), list) else []

    by_code: dict[str, list[dict[str, Any]]] = {}
    unknown_codes: list[str] = []
    for row in receipts:
        if not isinstance(row, dict):
            findings.append("PROVIDER_RECEIPT_NOT_OBJECT")
            continue
        code = row.get("provider_code")
        if code not in (CONTRACT.get("provider_codes") or {}):
            unknown_codes.append(str(code))
            continue
        by_code.setdefault(str(code), []).append(row)

    missing = sorted(code for code in required if len(by_code.get(code, [])) == 0)
    duplicates = sorted(code for code, rows in by_code.items() if len(rows) > 1)
    verified: list[str] = []
    hashes: dict[str, str] = {}
    subject_bad: list[str] = []
    provider_bad: list[str] = []
    deep_bad: list[str] = []
    currentness_bad: list[str] = []
    postmerge_bad: list[str] = []

    for code in sorted(by_code):
        rows = by_code[code]
        if len(rows) != 1:
            continue
        row = rows[0]
        spec = CONTRACT["provider_codes"][code]
        envelope_bad = _provider_envelope_bad(row)
        if envelope_bad:
            provider_bad.append(code + ":" + ",".join(envelope_bad))
            continue
        mismatch = _subject_mismatch(request, row)
        if mismatch:
            subject_bad.append(code + ":" + ",".join(mismatch))
            continue
        if row.get("result") != "PASS":
            provider_bad.append(code + ":RESULT")
            continue
        if row.get("provider_kind") != spec.get("provider_kind"):
            provider_bad.append(code + ":KIND")
            continue
        accepted = spec.get("accepted_modes")
        if isinstance(accepted, list) and row.get("provider_mode") not in accepted:
            provider_bad.append(code + ":MODE")
            continue

        if code in {"VALIDATE_LF_PACKS", "LF_BOOTSTRAP_REPRODUCIBILITY"}:
            bad = _workflow_common(row, spec)
            if bad:
                provider_bad.append(code + ":" + ",".join(bad))
                continue
        elif code == "LF_CONTRACT_CHECK":
            bad = _validate_contract_deep(row, spec)
            if bad:
                deep_bad.append(code + ":" + ",".join(bad))
                continue
        elif code == "CURRENTNESS_AUTHORITY":
            bad = _validate_currentness(request, row)
            if bad:
                currentness_bad.append(code + ":" + ",".join(bad))
                continue
        elif code == "EXTERNAL_RECONCILIATION_V7":
            bad = _validate_post_merge(request, row)
            if bad:
                postmerge_bad.append(code + ":" + ",".join(bad))
                continue

        verified.append(code)
        hashes[code] = row["receipt_sha256"]

    findings.extend("UNKNOWN_PROVIDER:" + x for x in sorted(set(unknown_codes)))
    findings.extend("SUBJECT_MISMATCH:" + x for x in subject_bad)
    findings.extend("PROVIDER_INVALID:" + x for x in provider_bad)
    findings.extend("CONTRACT_DEEP_INVALID:" + x for x in deep_bad)
    findings.extend("CURRENTNESS_INVALID:" + x for x in currentness_bad)
    findings.extend("POST_MERGE_INVALID:" + x for x in postmerge_bad)

    if unknown_codes:
        result = "BLOCK_CI_PROVIDER_UNKNOWN"
    elif duplicates:
        result = "BLOCK_CI_PROVIDER_DUPLICATE"
    elif missing:
        result = "BLOCK_CI_PROVIDER_MISSING"
    elif subject_bad:
        result = "BLOCK_CI_SUBJECT_MISMATCH"
    elif deep_bad:
        result = "BLOCK_CI_CONTRACT_DEEP_PROOF_INVALID"
    elif currentness_bad:
        result = "BLOCK_CI_CURRENTNESS_RECEIPT_INVALID"
    elif postmerge_bad:
        result = "BLOCK_CI_POST_MERGE_PROVIDER_INVALID"
    elif provider_bad or request_findings:
        result = "BLOCK_CI_PROVIDER_RESULT_INVALID"
    elif not set(required).issubset(set(verified)):
        result = "BLOCK_CI_PROVIDER_RESULT_INVALID"
        findings.append("REQUIRED_PROVIDER_NOT_VERIFIED")
    else:
        result = "PASS_CI_EVIDENCE_AGGREGATED"

    core = {
        "receipt_version": "LF_CI_EVIDENCE_RECEIPT_V1",
        "result": result,
        "repository_full_name": request.get("repository_full_name"),
        "candidate_head_sha": request.get("candidate_head_sha"),
        "base_sha": request.get("base_sha"),
        "target_branch": request.get("target_branch"),
        "pr_number": request.get("pr_number"),
        "evidence_purpose": request.get("evidence_purpose"),
        "requirement_profile": profile,
        "required_provider_codes": sorted(required),
        "verified_provider_codes": sorted(verified),
        "missing_provider_codes": missing,
        "duplicate_provider_codes": duplicates,
        "provider_receipt_sha256": dict(sorted(hashes.items())),
        "findings": findings,
        "claim_ceiling": CONTRACT["claim_ceiling"],
        "ci_evidence_complete": result == "PASS_CI_EVIDENCE_AGGREGATED",
        "e2e_closed": False,
        "qualification_closed": False,
        "semantic_review_closed": False,
        "merge_authorized": False,
        "runtime_authorized": False,
        "production_authorized": False,
        "golden_authorized": False
    }
    return core | {"receipt_sha256": canonical_sha256(core)}


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Aggregate governed LF CI provider receipts without remote calls.")
    ap.add_argument("request", type=Path)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()
    request = json.loads(ns.request.read_text(encoding="utf-8"))
    receipt = aggregate(request)
    rendered = json.dumps(receipt, sort_keys=True, indent=2) + "\n"
    if ns.output:
        ns.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if receipt["ci_evidence_complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
