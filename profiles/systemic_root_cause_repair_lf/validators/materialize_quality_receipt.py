#!/usr/bin/env python3
"""Deterministic SRCR canonical quality-receipt materializer.

This module does not perform semantic judgment. It may materialize a receipt only
after an independently produced semantic result passes the bound semantic-result
validator. The emitted receipt is immediately revalidated before return.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


closure = _load("srcr_materialize_closure", "closure_proof.py")
semantic_validator = _load(
    "srcr_materialize_semantic_validator", "validate_semantic_judge_result.py"
)
quality_validator = _load(
    "srcr_materialize_quality_validator", "validate_quality_receipt.py"
)

V06 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
VERDICT_TO_DECISION = {
    "PASS_INDEPENDENT_SEMANTIC": "PASS_TO_QUALITY_PACK",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR": "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR": "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE": "BLOCK_PIPELINE",
}


class QualityReceiptMaterializationError(ValueError):
    pass


def _canonical_json_sha256(value: Any) -> str:
    raw = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _text(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise QualityReceiptMaterializationError(name + "_REQUIRED")
    return value.strip()


def materialize_quality_receipt(
    candidate: Any,
    evidence_manifest: Any,
    semantic_result: Any,
    *,
    candidate_revision: str,
    semantic_execution_receipt_ref: str,
    issued_at: str,
    producer_execution_id: str | None = None,
    reviewer_execution_id: str | None = None,
    producer_execution_receipt_ref: str | None = None,
) -> dict[str, Any]:
    if not isinstance(candidate, dict):
        raise QualityReceiptMaterializationError("CANDIDATE_NOT_OBJECT")
    if not isinstance(evidence_manifest, dict):
        raise QualityReceiptMaterializationError("EVIDENCE_MANIFEST_NOT_OBJECT")
    if not isinstance(semantic_result, dict):
        raise QualityReceiptMaterializationError("SEMANTIC_RESULT_NOT_OBJECT")

    pack_id = candidate.get("profile_pack_id")
    evidence_manifest_sha256 = _canonical_json_sha256(evidence_manifest)
    semantic_gate = semantic_validator.evaluate(
        semantic_result,
        expected_evidence_manifest_sha256=(
            evidence_manifest_sha256 if pack_id == V06 else None
        ),
    )
    if semantic_gate.get("status") != "PASS":
        raise QualityReceiptMaterializationError(
            "SEMANTIC_RESULT_INVALID:"
            + ",".join(semantic_gate.get("blocking_codes") or [])
        )

    closure_errors, summary = closure.validate_v03_closure(candidate, evidence_manifest)
    if closure_errors:
        raise QualityReceiptMaterializationError(
            "CLOSURE_FLOOR_FAILED:"
            + ",".join(sorted({item["code"] for item in closure_errors}))
        )

    semantic_verdict = semantic_result.get("verdict")
    decision = VERDICT_TO_DECISION.get(semantic_verdict)
    if decision is None:
        raise QualityReceiptMaterializationError("SEMANTIC_VERDICT_UNSUPPORTED")

    boundary: dict[str, Any] = {
        "issuer": "CANONICAL_SRCR_MINI_JUDGE",
        "execution_mode": "INDEPENDENT_SEMANTIC_REVIEW",
        "reviewer_is_producer": False,
        "producer_context_available": False,
        "semantic_execution_receipt_ref": _text(
            semantic_execution_receipt_ref, "SEMANTIC_EXECUTION_RECEIPT_REF"
        ),
    }
    if pack_id == V06:
        producer_execution_id = _text(
            producer_execution_id, "PRODUCER_EXECUTION_ID"
        )
        reviewer_execution_id = _text(
            reviewer_execution_id, "REVIEWER_EXECUTION_ID"
        )
        producer_execution_receipt_ref = _text(
            producer_execution_receipt_ref, "PRODUCER_EXECUTION_RECEIPT_REF"
        )
        if producer_execution_id == reviewer_execution_id:
            raise QualityReceiptMaterializationError(
                "REVIEWER_EXECUTION_MUST_DIFFER_FROM_PRODUCER"
            )
        if producer_execution_receipt_ref == semantic_execution_receipt_ref:
            raise QualityReceiptMaterializationError(
                "REVIEWER_RECEIPT_MUST_DIFFER_FROM_PRODUCER"
            )
        boundary.update(
            {
                "producer_execution_id": producer_execution_id,
                "reviewer_execution_id": reviewer_execution_id,
                "producer_execution_receipt_ref": producer_execution_receipt_ref,
                "independence_evidence_refs": [
                    producer_execution_receipt_ref,
                    semantic_execution_receipt_ref,
                ],
            }
        )

    receipt = {
        "receipt_version": "SRCR_QUALITY_RECEIPT_V1",
        "profile_pack_id": pack_id,
        "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        "decision": decision,
        "review_boundary": boundary,
        "candidate_binding": {
            "candidate_revision": _text(candidate_revision, "CANDIDATE_REVISION"),
            "candidate_digest": closure.canonical_candidate_digest(candidate),
        },
        "evidence_binding": {
            "bundle_id": evidence_manifest.get("bundle_id"),
            "bundle_digest": closure.canonical_evidence_bundle_digest(evidence_manifest),
            **(
                {"evidence_manifest_sha256": evidence_manifest_sha256}
                if pack_id == V06
                else {}
            ),
        },
        "semantic_binding": {
            "semantic_result_digest": quality_validator.canonical_semantic_result_digest(
                semantic_result
            ),
            "semantic_verdict": semantic_verdict,
            "candidate_sha256": semantic_result.get("candidate_sha256"),
            "scope_packet_sha256": semantic_result.get("scope_packet_sha256"),
        },
        "proof_binding": {
            "required_obligation_ids": summary.get("required_obligation_ids") or [],
            "closed_obligation_ids": summary.get("closed_obligation_ids") or [],
            "open_obligation_ids": summary.get("open_obligation_ids") or [],
        },
        "blocking_codes": sorted(semantic_result.get("blocking_codes") or []),
        "issued_at": _text(issued_at, "ISSUED_AT"),
    }

    validation = quality_validator.validate_quality_receipt(
        receipt, candidate, evidence_manifest, semantic_result
    )
    if validation.get("status") != "PASS":
        raise QualityReceiptMaterializationError(
            "MATERIALIZED_RECEIPT_INVALID:"
            + ",".join(validation.get("blocking_codes") or [])
        )
    return receipt
