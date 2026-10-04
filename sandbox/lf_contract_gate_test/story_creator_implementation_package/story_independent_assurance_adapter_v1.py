"""SC-M4.3D thin consumer adapter for INDEPENDENT_ASSURANCE.

This module does not perform independent review, issue receipts, create judges,
change capability currentness, or mutate qualification. It only prepares the
exact STORY_IMPLEMENTATION_PACKAGE subject and validates a provider-bound
EVIDENCE_LEDGER receipt supplied by the governed readback path.
"""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Mapping

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PACKAGE_VERSION = "STORY_IMPLEMENTATION_PACKAGE_V1_1"
SUBJECT_TYPE = "STORY_IMPLEMENTATION_PACKAGE"
CAPABILITY_CODE = "INDEPENDENT_ASSURANCE"
ADAPTER_SCHEMA_VERSION = "STORY_IMPL_INDEPENDENT_ASSURANCE_ADAPTER_V1"
REQUIRED_DIMENSIONS = (
    "implementation_actionability",
    "source_fidelity",
    "reuse_correctness",
    "context_sufficiency",
    "acceptance_executability",
)


def canonical_package_sha256(package: Mapping[str, Any]) -> str:
    body = json.dumps(package, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def _blocked(code: str, **extra: Any) -> dict[str, Any]:
    return {"result": "BLOCKED", "code": code, **extra}


def prepare_story_independent_review(
    package: Mapping[str, Any],
    *,
    source_head_sha: str,
    capability_current: Mapping[str, Any],
) -> dict[str, Any]:
    if not isinstance(package, Mapping):
        return _blocked("STORY_IMPLEMENTATION_PACKAGE_INVALID")
    if not HEX40.fullmatch(source_head_sha or ""):
        return _blocked("STORY_SOURCE_HEAD_SHA_INVALID")

    story_identity = package.get("story_identity")
    decision_closure = package.get("decision_closure")
    if not isinstance(story_identity, Mapping) or not isinstance(decision_closure, Mapping):
        return _blocked("STORY_IMPLEMENTATION_PACKAGE_IDENTITY_INVALID")

    story_code = str(story_identity.get("story_code") or "").strip()
    canonical_story_sha = str(package.get("canonical_story_sha256") or "").strip()
    source_snapshot_sha = str(story_identity.get("source_snapshot_sha256") or "").strip()

    if (
        package.get("package_version") != PACKAGE_VERSION
        or package.get("canonical_evidence") != "STORY_PACK_A_Q"
        or not story_code
        or not HEX64.fullmatch(canonical_story_sha)
        or source_snapshot_sha != canonical_story_sha
    ):
        return _blocked("STORY_IMPLEMENTATION_PACKAGE_IDENTITY_INVALID")

    if (
        decision_closure.get("evidence_completeness_state") != "COMPLETE"
        or decision_closure.get("source_currentness_state") != "PROVEN_CURRENT"
    ):
        return _blocked("STORY_IMPLEMENTATION_PACKAGE_AUTHORITY_NOT_CURRENT")

    if capability_current.get("capability_code") != CAPABILITY_CODE:
        return _blocked("INDEPENDENT_ASSURANCE_NOT_CURRENT")
    version = str(capability_current.get("version") or "").strip()
    manifest_sha = str(capability_current.get("manifest_sha256") or "").strip()
    status = capability_current.get("status", "ACTIVE")
    if status != "ACTIVE" or not version or not HEX64.fullmatch(manifest_sha):
        return _blocked("INDEPENDENT_ASSURANCE_NOT_CURRENT")

    subject_sha = canonical_package_sha256(package)
    subject_ref = (
        f"STORY_CREATOR/STORY_IMPLEMENTATION_PACKAGE/{story_code}/"
        f"{PACKAGE_VERSION}/{canonical_story_sha}"
    )
    authority_ref = f"STORY_PACK_A_Q://{story_code}@{canonical_story_sha}"

    return {
        "result": "REVIEW_REQUIRED",
        "adapter_schema_version": ADAPTER_SCHEMA_VERSION,
        "consumer": "STORY_CREATOR_IMPLEMENTATION_SPEC_REFACTOR_V1/SC-M4.3D",
        "capability_code": CAPABILITY_CODE,
        "capability_version": version,
        "capability_manifest_sha256": manifest_sha,
        "subject_type": SUBJECT_TYPE,
        "subject_ref": subject_ref,
        "subject_sha256": subject_sha,
        "source_head_sha": source_head_sha,
        "authority_ref": authority_ref,
        "required_dimensions": list(REQUIRED_DIMENSIONS),
        "required_receipt": {
            "ledger": "private.lf_evidence_ledger_v1",
            "receipt_kind": "AUDIT_VERDICT",
            "verification_state": "VERIFIED",
            "independent": True,
            "independence_measure_state": "INDEPENDENT",
            "self_review": "FORBIDDEN",
        },
    }


def consume_story_independent_review(
    package: Mapping[str, Any],
    *,
    source_head_sha: str,
    capability_current: Mapping[str, Any],
    ledger_receipt: Mapping[str, Any] | None,
) -> dict[str, Any]:
    prepared = prepare_story_independent_review(
        package,
        source_head_sha=source_head_sha,
        capability_current=capability_current,
    )
    if prepared.get("result") != "REVIEW_REQUIRED":
        return prepared
    if not ledger_receipt:
        return _blocked("INDEPENDENT_REVIEW_RECEIPT_REQUIRED")

    payload = ledger_receipt.get("receipt_payload")
    if not isinstance(payload, Mapping):
        return _blocked("INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID")

    exact_bindings = {
        "capability_code": CAPABILITY_CODE,
        "receipt_kind": "AUDIT_VERDICT",
        "subject_type": prepared["subject_type"],
        "subject_ref": prepared["subject_ref"],
        "subject_sha256": prepared["subject_sha256"],
        "source_head_sha": prepared["source_head_sha"],
        "authority_ref": prepared["authority_ref"],
        "verification_state": "VERIFIED",
    }
    for key, expected in exact_bindings.items():
        if ledger_receipt.get(key) != expected:
            return _blocked("INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID", field=key)

    if (
        payload.get("capability_version") != prepared["capability_version"]
        or payload.get("capability_manifest_sha256") != prepared["capability_manifest_sha256"]
    ):
        return _blocked("INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID", field="capability_current")

    producer = str(payload.get("producer_identity") or "").strip()
    reviewer = str(payload.get("reviewer_identity") or "").strip()
    independence_measure = payload.get("independence_measure")
    if not isinstance(independence_measure, Mapping):
        return _blocked("INDEPENDENT_REVIEW_INDEPENDENCE_INVALID")
    if (
        not producer
        or not reviewer
        or producer == reviewer
        or payload.get("independent") is not True
        or independence_measure.get("state") != "INDEPENDENT"
        or payload.get("verdict") != "PASS"
    ):
        return _blocked("INDEPENDENT_REVIEW_INDEPENDENCE_INVALID")

    dimensions = payload.get("review_dimensions")
    evidence_refs = payload.get("evidence_refs")
    if not isinstance(dimensions, Mapping) or not isinstance(evidence_refs, list) or not evidence_refs:
        return _blocked("INDEPENDENT_REVIEW_CONTENT_INVALID")
    if any(dimensions.get(name) != "PASS" for name in REQUIRED_DIMENSIONS):
        return _blocked("INDEPENDENT_REVIEW_CONTENT_INVALID")

    receipt_id = str(ledger_receipt.get("receipt_id") or "").strip()
    receipt_sha = str(ledger_receipt.get("receipt_sha256") or "").strip()
    if not receipt_id or not HEX64.fullmatch(receipt_sha):
        return _blocked("INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID", field="receipt_identity")

    return {
        "result": "PASS",
        "adapter_schema_version": ADAPTER_SCHEMA_VERSION,
        "capability_code": CAPABILITY_CODE,
        "capability_version": prepared["capability_version"],
        "subject_type": prepared["subject_type"],
        "subject_ref": prepared["subject_ref"],
        "subject_sha256": prepared["subject_sha256"],
        "source_head_sha": prepared["source_head_sha"],
        "reviewer_identity": reviewer,
        "receipt_id": receipt_id,
        "receipt_sha256": receipt_sha,
        "authority_ref": prepared["authority_ref"],
        "verification_state": "VERIFIED",
    }
