from __future__ import annotations

import hashlib
import json
import re
from typing import Any, Dict, Iterable, List

from sandbox.lf_contract_gate_test.post_pase_final_evidence.final_evidence_v1 import (
    FinalEvidenceBlocked,
    controls_digest,
    verify_final_evidence_manifest,
)

HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")


class ClosureGateBlocked(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ClosureGateBlocked(code)


def _validate_identity(request: Dict[str, Any]) -> None:
    for field in ("post_pase_execution_id", "orchestrator_execution_id", "plan_id", "plan_digest", "merge_sha"):
        _require(isinstance(request.get(field), str) and bool(request[field]), f"MISSING_{field.upper()}")
    _require(bool(HEX64.fullmatch(request["plan_digest"])), "INVALID_PLAN_DIGEST")
    _require(bool(HEX40.fullmatch(request["merge_sha"])), "INVALID_MERGE_SHA")


def _validate_entry(request: Dict[str, Any]) -> None:
    entry = request.get("orchestrator_entry") or {}
    _require(entry.get("decision") == "ORCHESTRATOR_ENTRY_ACCEPTED", "ORCHESTRATOR_ENTRY_REQUIRED")
    _require(entry.get("orchestrator_execution_id") == request["orchestrator_execution_id"], "ENTRY_EXECUTION_CROSSBIND")
    _require(entry.get("plan_digest") == request["plan_digest"], "ENTRY_PLAN_CROSSBIND")
    _require(entry.get("capability_code") == "CLOSURE_GATE", "ENTRY_CAPABILITY_CROSSBIND")


def _forbid_collection_or_execution(request: Dict[str, Any]) -> None:
    forbidden = {
        "receipts",
        "raw_evidence",
        "verification_payload",
        "evidence_ledger",
        "ledger_receipts",
        "evidence_collection",
        "control_execution_request",
        "control_requests",
    }
    _require(not (forbidden & set(request)), "EVIDENCE_COLLECTION_OR_CONTROL_EXECUTION_FORBIDDEN")


def _validate_controls(controls: Any) -> List[Dict[str, str]]:
    _require(isinstance(controls, list) and controls, "PLAN_CONTROLS_REQUIRED")
    out: List[Dict[str, str]] = []
    seen = set()
    for c in controls:
        _require(isinstance(c, dict), "PLAN_CONTROL_SHAPE")
        code = c.get("control_code")
        disposition = c.get("disposition")
        _require(isinstance(code, str) and bool(code), "PLAN_CONTROL_CODE_REQUIRED")
        _require(disposition in {"REQUIRED", "NOT_APPLICABLE"}, "PLAN_CONTROL_DISPOSITION_INVALID")
        _require(code not in seen, "PLAN_CONTROL_DUPLICATE")
        seen.add(code)
        out.append({"control_code": code, "disposition": disposition})
    out.sort(key=lambda x: x["control_code"])
    return out


def _validate_plan_authority(request: Dict[str, Any], c_digest: str) -> None:
    proof = request.get("plan_authority_receipt") or {}
    _require(proof.get("schema_version") == "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1", "PLAN_AUTHORITY_SCHEMA")
    _require(proof.get("decision") in {"MATCH", "AUTHORIZED_DELTA"}, "PLAN_AUTHORITY_DECISION")
    _require(proof.get("plan_id") == request["plan_id"], "PLAN_AUTHORITY_PLAN_ID")
    _require(proof.get("plan_digest") == request["plan_digest"], "PLAN_AUTHORITY_PLAN_DIGEST")
    _require(proof.get("controls_digest") == c_digest, "PLAN_AUTHORITY_CONTROLS_DIGEST")


def _validate_manifest(request: Dict[str, Any], controls: List[Dict[str, str]], c_digest: str) -> Dict[str, Any]:
    manifest = request.get("final_evidence_manifest")
    _require(isinstance(manifest, dict), "FINAL_EVIDENCE_MANIFEST_REQUIRED")
    try:
        verify_final_evidence_manifest(manifest)
    except FinalEvidenceBlocked as exc:
        raise ClosureGateBlocked(f"FINAL_EVIDENCE_INVALID:{exc}") from exc

    for field in ("post_pase_execution_id", "orchestrator_execution_id", "plan_id", "plan_digest", "merge_sha"):
        _require(manifest.get(field) == request[field], f"FINAL_EVIDENCE_{field.upper()}_MISMATCH")
    _require(manifest.get("controls_digest") == c_digest, "FINAL_EVIDENCE_CONTROLS_DIGEST_MISMATCH")

    required = [c["control_code"] for c in controls if c["disposition"] == "REQUIRED"]
    na = [c["control_code"] for c in controls if c["disposition"] == "NOT_APPLICABLE"]
    _require(manifest.get("required_controls") == required, "FINAL_EVIDENCE_REQUIRED_CONTROLS_MISMATCH")
    _require(manifest.get("not_applicable_controls") == na, "FINAL_EVIDENCE_NA_CONTROLS_MISMATCH")
    refs = manifest.get("receipt_refs") or []
    _require([r.get("control_code") for r in refs] == required, "FINAL_EVIDENCE_RECEIPT_CONTROL_ORDER_MISMATCH")
    return manifest


def closure_request_digest(request: Dict[str, Any], manifest: Dict[str, Any]) -> str:
    return _sha256(
        {
            "schema_version": "LF_POST_PASE_CLOSURE_REQUEST_DIGEST_V1",
            "post_pase_execution_id": request["post_pase_execution_id"],
            "orchestrator_execution_id": request["orchestrator_execution_id"],
            "plan_id": request["plan_id"],
            "plan_digest": request["plan_digest"],
            "merge_sha": request["merge_sha"],
            "final_evidence_manifest_sha256": manifest["manifest_sha256"],
        }
    )


def _validate_waivers(
    request: Dict[str, Any],
    failed_controls: List[str],
    blocked_controls: List[str],
    request_digest: str,
) -> List[Dict[str, str]]:
    waivers = request.get("waiver_receipts") or []
    _require(isinstance(waivers, list), "WAIVER_RECEIPTS_SHAPE")
    if blocked_controls:
        _require(not waivers, "WAIVER_FOR_BLOCKED_CONTROL_FORBIDDEN")
        return []
    if not failed_controls:
        _require(not waivers, "EXTRA_WAIVER_WITHOUT_FAILED_CONTROL")
        return []

    seen = set()
    valid: List[Dict[str, str]] = []
    for waiver in waivers:
        _require(isinstance(waiver, dict), "WAIVER_RECEIPT_SHAPE")
        _require(waiver.get("schema_version") == "LF_WAIVER_AUTHORITY_RECEIPT_V1", "WAIVER_RECEIPT_SCHEMA")
        _require(waiver.get("decision") == "WAIVER_AUTHORIZED", "WAIVER_NOT_AUTHORIZED")
        control = waiver.get("control_id")
        _require(control in failed_controls, "WAIVER_SCOPE_NOT_FAILED_CONTROL")
        _require(control not in seen, "WAIVER_DUPLICATE_CONTROL")
        _require(waiver.get("post_pase_execution_id") == request["post_pase_execution_id"], "WAIVER_EXECUTION_MISMATCH")
        _require(waiver.get("plan_digest") == request["plan_digest"], "WAIVER_PLAN_DIGEST_MISMATCH")
        _require(waiver.get("merge_sha") == request["merge_sha"], "WAIVER_MERGE_SHA_MISMATCH")
        _require(waiver.get("consumer_request_digest") == request_digest, "WAIVER_REQUEST_DIGEST_MISMATCH")
        grant_sha = waiver.get("grant_sha256")
        readback = waiver.get("consumption_readback_digest")
        _require(isinstance(grant_sha, str) and bool(HEX64.fullmatch(grant_sha)), "WAIVER_GRANT_DIGEST_INVALID")
        _require(isinstance(readback, str) and bool(HEX64.fullmatch(readback)), "WAIVER_CONSUMPTION_DIGEST_INVALID")
        seen.add(control)
        valid.append(
            {
                "control_id": control,
                "grant_sha256": grant_sha,
                "consumption_readback_digest": readback,
            }
        )
    valid.sort(key=lambda x: x["control_id"])
    return valid


def build_closure_verdict(request: Dict[str, Any]) -> Dict[str, Any]:
    _validate_identity(request)
    _validate_entry(request)
    _forbid_collection_or_execution(request)
    controls = _validate_controls(request.get("plan_controls"))
    c_digest = controls_digest(controls)
    _validate_plan_authority(request, c_digest)
    manifest = _validate_manifest(request, controls, c_digest)

    refs = manifest["receipt_refs"]
    outcomes = {r["control_code"]: r["terminal_outcome"] for r in refs}
    blocked_controls = sorted([c for c, outcome in outcomes.items() if outcome == "BLOCKED"])
    failed_controls = sorted([c for c, outcome in outcomes.items() if outcome == "FAIL"])
    request_digest = closure_request_digest(request, manifest)
    waiver_refs = _validate_waivers(request, failed_controls, blocked_controls, request_digest)
    waived_controls = sorted([w["control_id"] for w in waiver_refs])

    if blocked_controls:
        verdict = "BLOCKED"
    elif failed_controls:
        verdict = "WAIVED" if waived_controls == failed_controls else "FAIL"
    else:
        verdict = "PASS"

    result = {
        "schema_version": "LF_POST_PASE_CLOSURE_VERDICT_V1",
        "verdict": verdict,
        "terminal_status": "CLOSED" if verdict in {"PASS", "WAIVED"} else "NOT_CLOSED",
        "post_pase_execution_id": request["post_pase_execution_id"],
        "orchestrator_execution_id": request["orchestrator_execution_id"],
        "plan_id": request["plan_id"],
        "plan_digest": request["plan_digest"],
        "merge_sha": request["merge_sha"],
        "controls_digest": c_digest,
        "final_evidence_manifest_sha256": manifest["manifest_sha256"],
        "closure_request_digest": request_digest,
        "failed_controls": failed_controls,
        "blocked_controls": blocked_controls,
        "waived_controls": waived_controls,
        "waiver_refs": waiver_refs,
        "evidence_collection_performed": False,
        "control_execution_performed": False,
        "promotion_performed": False,
        "lifecycle_mutation_performed": False,
    }
    result["verdict_sha256"] = _sha256(result)
    return result
