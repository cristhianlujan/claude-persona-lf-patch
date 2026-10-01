from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Dict, Iterable, List

HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")


class FinalEvidenceBlocked(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def controls_digest(controls: Iterable[Dict[str, str]]) -> str:
    normalized = sorted(
        ({"control_code": c["control_code"], "disposition": c["disposition"]} for c in controls),
        key=lambda x: x["control_code"],
    )
    return _sha256(normalized)


def manifest_digest(manifest_without_digest: Dict[str, Any]) -> str:
    return _sha256(manifest_without_digest)


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise FinalEvidenceBlocked(code)


def _validate_identity(request: Dict[str, Any]) -> None:
    for field in (
        "post_pase_execution_id",
        "orchestrator_execution_id",
        "plan_id",
        "plan_digest",
        "merge_sha",
    ):
        _require(isinstance(request.get(field), str) and bool(request[field]), f"MISSING_{field.upper()}")
    _require(bool(HEX64.fullmatch(request["plan_digest"])), "INVALID_PLAN_DIGEST")
    _require(bool(HEX40.fullmatch(request["merge_sha"])), "INVALID_MERGE_SHA")


def _validate_entry(request: Dict[str, Any]) -> None:
    entry = request.get("orchestrator_entry") or {}
    _require(entry.get("decision") == "ORCHESTRATOR_ENTRY_ACCEPTED", "ORCHESTRATOR_ENTRY_REQUIRED")
    _require(entry.get("orchestrator_execution_id") == request["orchestrator_execution_id"], "ENTRY_EXECUTION_CROSSBIND")
    _require(entry.get("plan_digest") == request["plan_digest"], "ENTRY_PLAN_CROSSBIND")
    _require(entry.get("capability_code") == "FINAL_EVIDENCE", "ENTRY_CAPABILITY_CROSSBIND")


def _validate_controls(request: Dict[str, Any]) -> List[Dict[str, str]]:
    controls = request.get("controls")
    _require(isinstance(controls, list) and len(controls) > 0, "CONTROLS_REQUIRED")
    seen = set()
    normalized: List[Dict[str, str]] = []
    for control in controls:
        code = control.get("control_code") if isinstance(control, dict) else None
        disposition = control.get("disposition") if isinstance(control, dict) else None
        _require(isinstance(code, str) and bool(code), "CONTROL_CODE_REQUIRED")
        _require(disposition in {"REQUIRED", "NOT_APPLICABLE"}, "CONTROL_DISPOSITION_INVALID")
        _require(code not in seen, "DUPLICATE_CONTROL")
        seen.add(code)
        normalized.append({"control_code": code, "disposition": disposition})
    normalized.sort(key=lambda x: x["control_code"])
    return normalized


def _validate_plan_authority(request: Dict[str, Any], computed_controls_digest: str) -> None:
    proof = request.get("plan_authority_receipt") or {}
    _require(proof.get("schema_version") == "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1", "PLAN_AUTHORITY_SCHEMA")
    _require(proof.get("decision") in {"MATCH", "AUTHORIZED_DELTA"}, "PLAN_AUTHORITY_DECISION")
    _require(proof.get("plan_id") == request["plan_id"], "PLAN_AUTHORITY_PLAN_ID")
    _require(proof.get("plan_digest") == request["plan_digest"], "PLAN_AUTHORITY_PLAN_DIGEST")
    _require(proof.get("controls_digest") == computed_controls_digest, "PLAN_AUTHORITY_CONTROLS_DIGEST")


def _receipt_ref(receipt: Dict[str, Any]) -> Dict[str, str]:
    return {
        "control_code": receipt["control_code"],
        "receipt_id": receipt["receipt_id"],
        "receipt_sha256": receipt["receipt_sha256"],
    }


def _validate_receipts(request: Dict[str, Any], controls: List[Dict[str, str]]) -> List[Dict[str, str]]:
    receipts = request.get("receipts")
    _require(isinstance(receipts, list), "RECEIPTS_REQUIRED")
    required = {c["control_code"] for c in controls if c["disposition"] == "REQUIRED"}
    not_applicable = {c["control_code"] for c in controls if c["disposition"] == "NOT_APPLICABLE"}
    by_control: Dict[str, Dict[str, Any]] = {}
    seen_receipts = set()

    for receipt in receipts:
        _require(isinstance(receipt, dict), "RECEIPT_SHAPE")
        control_code = receipt.get("control_code")
        _require(control_code in required, "EXTRA_OR_NA_RECEIPT")
        _require(control_code not in by_control, "DUPLICATE_CONTROL_RECEIPT")
        receipt_id = receipt.get("receipt_id")
        receipt_sha = receipt.get("receipt_sha256")
        _require(isinstance(receipt_id, str) and bool(receipt_id), "RECEIPT_ID_REQUIRED")
        _require(receipt_id not in seen_receipts, "DUPLICATE_RECEIPT_ID")
        _require(isinstance(receipt_sha, str) and bool(HEX64.fullmatch(receipt_sha)), "RECEIPT_SHA_INVALID")
        _require(receipt.get("verification_state") == "VERIFIED", "RECEIPT_NOT_VERIFIED")
        _require(receipt.get("source_head_sha") == request["merge_sha"], "RECEIPT_SOURCE_HEAD_MISMATCH")
        _require(receipt.get("plan_digest") == request["plan_digest"], "RECEIPT_PLAN_DIGEST_MISMATCH")
        for field in ("execution_id", "capability_code", "gate_code", "subject_ref", "subject_sha256", "authority_ref", "resolver_id"):
            _require(isinstance(receipt.get(field), str) and bool(receipt[field]), f"RECEIPT_{field.upper()}_REQUIRED")
        _require(bool(HEX64.fullmatch(receipt["subject_sha256"])), "RECEIPT_SUBJECT_SHA_INVALID")
        by_control[control_code] = receipt
        seen_receipts.add(receipt_id)

    _require(set(by_control) == required, "REQUIRED_RECEIPT_SET_MISMATCH")
    _require(not (set(by_control) & not_applicable), "NA_CONTROL_HAS_RECEIPT")
    return [_receipt_ref(by_control[code]) for code in sorted(by_control)]


def build_final_evidence_manifest(request: Dict[str, Any]) -> Dict[str, Any]:
    _validate_identity(request)
    _validate_entry(request)
    controls = _validate_controls(request)
    c_digest = controls_digest(controls)
    _validate_plan_authority(request, c_digest)
    receipt_refs = _validate_receipts(request, controls)

    required_controls = [c["control_code"] for c in controls if c["disposition"] == "REQUIRED"]
    not_applicable_controls = [c["control_code"] for c in controls if c["disposition"] == "NOT_APPLICABLE"]
    manifest = {
        "schema_version": "LF_POST_PASE_FINAL_EVIDENCE_MANIFEST_V1",
        "decision": "FINAL_EVIDENCE_MANIFEST_READY",
        "post_pase_execution_id": request["post_pase_execution_id"],
        "orchestrator_execution_id": request["orchestrator_execution_id"],
        "plan_id": request["plan_id"],
        "plan_digest": request["plan_digest"],
        "merge_sha": request["merge_sha"],
        "controls_digest": c_digest,
        "required_controls": required_controls,
        "not_applicable_controls": not_applicable_controls,
        "receipt_refs": receipt_refs,
        "receipt_count": len(receipt_refs),
        "raw_evidence_embedded": False,
        "closure_verdict": None,
    }
    manifest["manifest_sha256"] = manifest_digest(manifest)
    return manifest
