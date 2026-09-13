#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
REPO = "cristhianlujan/claude-persona-lf-patch"
QUALITY_PACK_SHA = "d4051d9c57fdfd09741da5ba2718c032eac56c92"
CANDIDATE_SHA = "d268fd871f2e18588f9b8084e6a3f6c6e07aa438"
REQUIRED_QP_KEYS = {
    "independent_review_contract_ref",
    "quality_gate_contract_ref",
    "lf_quality_controls_ref",
    "score_rubric_ref",
    "mini_judge_ref",
    "quality_review_schema_ref",
    "independent_receipt_schema_ref",
    "independent_receipt_validator_ref",
}


def git_blob_sha(text: str) -> str:
    raw = text.encode("utf-8")
    header = f"blob {len(raw)}\0".encode("ascii")
    return hashlib.sha1(header + raw).hexdigest()


def _block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": "BLOCKED", "code": code, **extra}


def validate_bundle(bundle: dict[str, Any]) -> dict[str, Any]:
    if bundle.get("execution_mode") != "INDEPENDENT_CHAT_CONTEXT":
        return _block("BLOCK_REVIEW_MODE_NOT_INDEPENDENT_CHAT")
    if bundle.get("producer_semantic_verdict") is not None:
        return _block("BLOCK_PRODUCER_SEMANTIC_VERDICT_PRESENT")
    snapshot = bundle.get("candidate_snapshot") or {}
    if snapshot.get("s31_candidate_head") != CANDIDATE_SHA:
        return _block("BLOCK_CANDIDATE_SNAPSHOT_MISMATCH")
    qp = bundle.get("quality_pack") or {}
    missing = sorted(REQUIRED_QP_KEYS - set(qp))
    if missing:
        return _block("BLOCK_QUALITY_PACK_REFS_MISSING", missing=missing)
    for key in REQUIRED_QP_KEYS:
        ref = qp[key]
        prefix = f"github://{REPO}@{QUALITY_PACK_SHA}/profiles/quality_pack/"
        if not isinstance(ref, str) or not ref.startswith(prefix):
            return _block("BLOCK_QUALITY_PACK_REF_NOT_FROZEN", key=key, ref=ref)
    frozen = bundle.get("frozen_artifacts")
    if not isinstance(frozen, list) or not frozen:
        return _block("BLOCK_FROZEN_ARTIFACTS_MISSING")
    for index, item in enumerate(frozen):
        if not isinstance(item, dict) or not item.get("path") or not item.get("role"):
            return _block("BLOCK_FROZEN_ARTIFACT_INVALID", index=index)
    return {"status": "PASS", "code": "PASS_REVIEW_BUNDLE"}


def _extract(pattern: str, text: str) -> str | None:
    match = re.search(pattern, text)
    return match.group(1) if match else None


def validate_handoff(text: str, bundle_text: str, review_case_id: str) -> dict[str, Any]:
    required_tokens = [
        "INDEPENDENT_CHAT_CONTEXT",
        "reviewer_is_producer = false",
        "producer_context_available = false",
        "external_paid_model_used = false",
        "automated_semantic_judge_implemented = false",
        "profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json",
        "s31_lane_reviews",
        review_case_id,
    ]
    missing = [token for token in required_tokens if token not in text]
    if missing:
        return _block("BLOCK_HANDOFF_CANONICAL_TOKENS_MISSING", missing=missing)
    forbidden = ["S31_ABC_INDEPENDENT_REVIEW_V0_2\"", "S31_DG_INDEPENDENT_REVIEW_V0_1\"", "\"overall_verdict\""]
    present = [token for token in forbidden if token in text]
    if present:
        return _block("BLOCK_PARALLEL_RECEIPT_CONTRACT_PRESENT", present=present)
    artifact_ref = _extract(r"`artifact_ref`: `([^`]+)`", text)
    artifact_sha = _extract(r"`artifact_sha_or_digest`: `([0-9a-f]{40})`", text)
    if not artifact_ref or not re.match(rf"^github://{re.escape(REPO)}@[0-9a-f]{{40}}/", artifact_ref):
        return _block("BLOCK_REVIEW_ARTIFACT_REF_NOT_IMMUTABLE", artifact_ref=artifact_ref)
    actual_blob_sha = git_blob_sha(bundle_text)
    if artifact_sha != actual_blob_sha:
        return _block("BLOCK_REVIEW_BUNDLE_SHA_MISMATCH", declared=artifact_sha, actual=actual_blob_sha)
    if "producer provides no semantic target verdict" not in text.lower():
        return _block("BLOCK_NO_TARGET_VERDICT_RULE_MISSING")
    return {"status": "PASS", "code": "PASS_REVIEW_HANDOFF"}


def evaluate_pair(bundle: dict[str, Any], handoff_text: str, bundle_text: str, review_case_id: str) -> dict[str, Any]:
    b = validate_bundle(bundle)
    if b["status"] != "PASS":
        return b
    return validate_handoff(handoff_text, bundle_text, review_case_id)


def main() -> int:
    cases = [
        ("ABC", "s31_abc_independent_review_bundle_v0_4.json", "S31_ABC_INDEPENDENT_REVIEW_HANDOFF_V0_2.md", "S31-ABC-IR-001"),
        ("DG", "s31_dg_independent_review_bundle_v0_3.json", "S31_DG_INDEPENDENT_REVIEW_HANDOFF_V0_1.md", "S31-DG-IR-001"),
    ]
    results = []
    failed = False
    for name, bundle_name, handoff_name, case_id in cases:
        bundle_text = (ROOT / bundle_name).read_text(encoding="utf-8")
        bundle = json.loads(bundle_text)
        handoff = (ROOT / handoff_name).read_text(encoding="utf-8")
        result = evaluate_pair(bundle, handoff, bundle_text, case_id)
        failed = failed or result.get("status") != "PASS"
        results.append({"case": name, **result})
    print(json.dumps({"contract":"S31_INDEPENDENT_REVIEW_INTAKE_V0_1","results":results,"result":"FAIL" if failed else "PASS"}, indent=2, sort_keys=True))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
