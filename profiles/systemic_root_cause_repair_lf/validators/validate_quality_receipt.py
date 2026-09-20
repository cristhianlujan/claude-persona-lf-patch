#!/usr/bin/env python3
"""Deterministic verifier for SRCR V0.3 canonical quality receipts.

This verifier binds an externally issued quality decision to exact candidate,
evidence and semantic-result bytes. It does not perform semantic judgment and
cannot manufacture a PASS independently of the canonical SRCR mini-judge path.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load_local(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


closure = _load_local("srcr_quality_closure", "closure_proof.py")
semantic_validator = _load_local("srcr_quality_semantic_result", "validate_semantic_judge_result.py")

V03 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3"
PASS_SEMANTIC = "PASS_INDEPENDENT_SEMANTIC"
PASS_DECISION = "PASS_TO_QUALITY_PACK"
VERDICT_TO_DECISION = {
    "PASS_INDEPENDENT_SEMANTIC": "PASS_TO_QUALITY_PACK",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR": "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR": "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE": "BLOCK_PIPELINE",
}


def _err(code: str, path: str = "$", message: str = "") -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def canonical_semantic_result_digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_quality_receipt(
    receipt: Any,
    candidate: Any,
    evidence_manifest: Any,
    semantic_result: Any,
) -> dict[str, Any]:
    errors: list[dict[str, str]] = []

    if not isinstance(receipt, dict):
        return {
            "status": "FAIL",
            "blocking_codes": ["SRCR_QUALITY_RECEIPT_NOT_OBJECT"],
            "errors": [_err("SRCR_QUALITY_RECEIPT_NOT_OBJECT")],
            "canonical_quality_accepted": False,
        }

    if not isinstance(candidate, dict) or candidate.get("profile_pack_id") != V03:
        errors.append(_err("SRCR_QUALITY_RECEIPT_REQUIRES_V03", "$.candidate.profile_pack_id"))
    if isinstance(candidate, dict) and "quality_receipt" in candidate:
        errors.append(_err("SRCR_CANDIDATE_SELF_ISSUED_QUALITY_RECEIPT", "$.candidate.quality_receipt"))

    expected_constants = {
        "receipt_version": "SRCR_QUALITY_RECEIPT_V1",
        "profile_pack_id": V03,
        "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
    }
    for field, expected in expected_constants.items():
        if receipt.get(field) != expected:
            errors.append(_err("SRCR_QUALITY_RECEIPT_CONSTANT_MISMATCH", f"$.receipt.{field}", str(expected)))

    boundary = receipt.get("review_boundary")
    if not isinstance(boundary, dict):
        errors.append(_err("SRCR_QUALITY_REVIEW_BOUNDARY_MISSING", "$.receipt.review_boundary"))
        boundary = {}
    if boundary.get("issuer") != "CANONICAL_SRCR_MINI_JUDGE":
        errors.append(_err("SRCR_QUALITY_ISSUER_INVALID", "$.receipt.review_boundary.issuer"))
    if boundary.get("execution_mode") != "INDEPENDENT_SEMANTIC_REVIEW":
        errors.append(_err("SRCR_QUALITY_EXECUTION_MODE_INVALID", "$.receipt.review_boundary.execution_mode"))
    if boundary.get("reviewer_is_producer") is not False:
        errors.append(_err("SRCR_QUALITY_REVIEWER_NOT_INDEPENDENT", "$.receipt.review_boundary.reviewer_is_producer"))
    if boundary.get("producer_context_available") is not False:
        errors.append(_err("SRCR_QUALITY_PRODUCER_CONTEXT_AVAILABLE", "$.receipt.review_boundary.producer_context_available"))
    if not _nonempty(boundary.get("semantic_execution_receipt_ref")):
        errors.append(_err("SRCR_SEMANTIC_EXECUTION_RECEIPT_REF_REQUIRED", "$.receipt.review_boundary.semantic_execution_receipt_ref"))

    closure_errors, summary = closure.validate_v03_closure(candidate, evidence_manifest)
    if closure_errors:
        errors.append(
            _err(
                "SRCR_QUALITY_CLOSURE_FLOOR_FAILED",
                "$.candidate.closure_proof",
                ",".join(sorted({x["code"] for x in closure_errors})),
            )
        )

    semantic_gate = semantic_validator.evaluate(semantic_result)
    if semantic_gate.get("status") != "PASS":
        errors.append(
            _err(
                "SRCR_QUALITY_SEMANTIC_RESULT_INVALID",
                "$.semantic_result",
                ",".join(semantic_gate.get("blocking_codes") or []),
            )
        )

    candidate_binding = receipt.get("candidate_binding")
    if not isinstance(candidate_binding, dict):
        errors.append(_err("SRCR_QUALITY_CANDIDATE_BINDING_MISSING", "$.receipt.candidate_binding"))
        candidate_binding = {}

    proof = candidate.get("closure_proof") if isinstance(candidate, dict) and isinstance(candidate.get("closure_proof"), dict) else {}
    proof_candidate_binding = proof.get("candidate_binding") if isinstance(proof.get("candidate_binding"), dict) else {}

    actual_candidate_digest = closure.canonical_candidate_digest(candidate) if isinstance(candidate, dict) else None
    if candidate_binding.get("candidate_revision") != proof_candidate_binding.get("candidate_revision"):
        errors.append(_err("SRCR_QUALITY_CANDIDATE_REVISION_MISMATCH", "$.receipt.candidate_binding.candidate_revision"))
    if candidate_binding.get("candidate_digest") != actual_candidate_digest:
        errors.append(_err("SRCR_QUALITY_CANDIDATE_DIGEST_MISMATCH", "$.receipt.candidate_binding.candidate_digest"))
    if proof_candidate_binding.get("candidate_digest") != actual_candidate_digest:
        errors.append(_err("SRCR_QUALITY_CANDIDATE_PROOF_DIGEST_MISMATCH", "$.candidate.closure_proof.candidate_binding.candidate_digest"))

    evidence_binding = receipt.get("evidence_binding")
    if not isinstance(evidence_binding, dict):
        errors.append(_err("SRCR_QUALITY_EVIDENCE_BINDING_MISSING", "$.receipt.evidence_binding"))
        evidence_binding = {}

    actual_bundle_digest = closure.canonical_evidence_bundle_digest(evidence_manifest) if isinstance(evidence_manifest, dict) else None
    if evidence_binding.get("bundle_id") != proof_candidate_binding.get("evidence_bundle_id"):
        errors.append(_err("SRCR_QUALITY_EVIDENCE_BUNDLE_ID_MISMATCH", "$.receipt.evidence_binding.bundle_id"))
    if evidence_binding.get("bundle_digest") != actual_bundle_digest:
        errors.append(_err("SRCR_QUALITY_EVIDENCE_BUNDLE_DIGEST_MISMATCH", "$.receipt.evidence_binding.bundle_digest"))
    if proof_candidate_binding.get("evidence_bundle_digest") != actual_bundle_digest:
        errors.append(_err("SRCR_QUALITY_CANDIDATE_EVIDENCE_DIGEST_MISMATCH", "$.candidate.closure_proof.candidate_binding.evidence_bundle_digest"))

    semantic_binding = receipt.get("semantic_binding")
    if not isinstance(semantic_binding, dict):
        errors.append(_err("SRCR_QUALITY_SEMANTIC_BINDING_MISSING", "$.receipt.semantic_binding"))
        semantic_binding = {}

    semantic_digest = canonical_semantic_result_digest(semantic_result) if isinstance(semantic_result, dict) else None
    if semantic_binding.get("semantic_result_digest") != semantic_digest:
        errors.append(_err("SRCR_QUALITY_SEMANTIC_RESULT_DIGEST_MISMATCH", "$.receipt.semantic_binding.semantic_result_digest"))

    semantic_verdict = semantic_result.get("verdict") if isinstance(semantic_result, dict) else None
    if semantic_binding.get("semantic_verdict") != semantic_verdict:
        errors.append(_err("SRCR_QUALITY_SEMANTIC_VERDICT_MISMATCH", "$.receipt.semantic_binding.semantic_verdict"))

    expected_candidate_sha = actual_candidate_digest.removeprefix("sha256:") if isinstance(actual_candidate_digest, str) else None
    if semantic_binding.get("candidate_sha256") != expected_candidate_sha:
        errors.append(_err("SRCR_QUALITY_SEMANTIC_CANDIDATE_SHA_MISMATCH", "$.receipt.semantic_binding.candidate_sha256"))
    if isinstance(semantic_result, dict) and semantic_result.get("candidate_sha256") != expected_candidate_sha:
        errors.append(_err("SRCR_SEMANTIC_RESULT_CANDIDATE_SHA_MISMATCH", "$.semantic_result.candidate_sha256"))
    if isinstance(semantic_result, dict) and semantic_binding.get("scope_packet_sha256") != semantic_result.get("scope_packet_sha256"):
        errors.append(_err("SRCR_QUALITY_SCOPE_PACKET_SHA_MISMATCH", "$.receipt.semantic_binding.scope_packet_sha256"))

    proof_receipt = receipt.get("proof_binding")
    if not isinstance(proof_receipt, dict):
        errors.append(_err("SRCR_QUALITY_PROOF_BINDING_MISSING", "$.receipt.proof_binding"))
        proof_receipt = {}

    required_ids = summary.get("required_obligation_ids") if isinstance(summary, dict) else []
    closed_ids = summary.get("closed_obligation_ids") if isinstance(summary, dict) else []
    open_ids = summary.get("open_obligation_ids") if isinstance(summary, dict) else []

    if sorted(proof_receipt.get("required_obligation_ids") or []) != sorted(required_ids or []):
        errors.append(_err("SRCR_QUALITY_REQUIRED_PROOF_SET_MISMATCH", "$.receipt.proof_binding.required_obligation_ids"))
    if sorted(proof_receipt.get("closed_obligation_ids") or []) != sorted(closed_ids or []):
        errors.append(_err("SRCR_QUALITY_CLOSED_PROOF_SET_MISMATCH", "$.receipt.proof_binding.closed_obligation_ids"))
    if sorted(proof_receipt.get("open_obligation_ids") or []) != sorted(open_ids or []):
        errors.append(_err("SRCR_QUALITY_OPEN_PROOF_SET_MISMATCH", "$.receipt.proof_binding.open_obligation_ids"))

    decision = receipt.get("decision")
    expected_decision = VERDICT_TO_DECISION.get(semantic_verdict)
    if decision != expected_decision:
        errors.append(_err("SRCR_QUALITY_DECISION_SEMANTIC_MISMATCH", "$.receipt.decision", str(expected_decision)))

    semantic_blockers = sorted(semantic_result.get("blocking_codes") or []) if isinstance(semantic_result, dict) else []
    receipt_blockers = sorted(receipt.get("blocking_codes") or []) if isinstance(receipt.get("blocking_codes"), list) else []
    if receipt_blockers != semantic_blockers:
        errors.append(_err("SRCR_QUALITY_BLOCKING_CODES_MISMATCH", "$.receipt.blocking_codes"))

    if decision == PASS_DECISION:
        if semantic_verdict != PASS_SEMANTIC:
            errors.append(_err("SRCR_QUALITY_PASS_WITHOUT_SEMANTIC_PASS", "$.receipt.decision"))
        if summary.get("computed_handoff_ready") is not True:
            errors.append(_err("SRCR_QUALITY_PASS_WITHOUT_DERIVED_READINESS", "$.candidate.closure_proof"))
        if open_ids:
            errors.append(_err("SRCR_QUALITY_PASS_WITH_OPEN_PROOFS", "$.receipt.proof_binding.open_obligation_ids"))
        if receipt_blockers:
            errors.append(_err("SRCR_QUALITY_PASS_WITH_BLOCKERS", "$.receipt.blocking_codes"))

    if not _nonempty(receipt.get("issued_at")):
        errors.append(_err("SRCR_QUALITY_ISSUED_AT_REQUIRED", "$.receipt.issued_at"))

    codes = sorted({e["code"] for e in errors})
    return {
        "status": "PASS" if not errors else "FAIL",
        "blocking_codes": codes,
        "errors": errors,
        "quality_role": "CANONICAL_SRCR_QUALITY_RECEIPT_VERIFIER",
        "canonical_quality_accepted": not errors and decision == PASS_DECISION,
        "decision": decision,
        "candidate_digest": actual_candidate_digest,
        "evidence_bundle_digest": actual_bundle_digest,
        "semantic_result_digest": semantic_digest,
    }


def main() -> int:
    if len(sys.argv) != 5:
        print(json.dumps({"status": "FAIL", "blocking_codes": ["USAGE_QUALITY_RECEIPT_VALIDATOR"]}))
        return 2
    receipt, candidate, evidence, semantic = [
        json.load(open(path, "r", encoding="utf-8")) for path in sys.argv[1:]
    ]
    result = validate_quality_receipt(receipt, candidate, evidence, semantic)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
