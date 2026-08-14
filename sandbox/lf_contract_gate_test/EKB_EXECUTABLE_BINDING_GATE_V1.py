#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
BINDINGS = {
    "EKB-P0-003": "ATOMIC_INJECTIVE_MATCH",
    "EKB-P0-014": "TEXT_GROUPING_SHORT_PHRASE",
    "EKB-P0-016": "OCR_RESIDUAL_FAIL_CLOSED",
    "EKB-P0-017": "OCR_FAMILY_INDEPENDENCE_DISCLOSURE",
    "EKB-P0-020": "SHORT_OCR_MATERIALITY",
    "EKB-P0-021": "TEXT_MATCH_GLOBAL_SEMANTICS",
    "EKB-P0-022": "VISUAL_OBJECT_SCALE_EQUIVALENCE",
    "AUD-020": "FRESH_SOURCE_BINDING",
    "AUD-030": "WRAPPER_STRUCTURAL_DELEGATION",
}
ALLOWED_RESULTS = {"PASS", "FAIL", "BLOCKED", "HUMAN_REVIEW_REQUIRED"}


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def validate_receipt(code: str, receipt: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(receipt, dict):
        return [f"{code}:RECEIPT_NOT_OBJECT"]
    if receipt.get("validation_id") != BINDINGS[code]:
        errors.append(f"{code}:VALIDATION_ID_MISMATCH")
    if receipt.get("executed") is not True:
        errors.append(f"{code}:NOT_EXECUTED")
    if receipt.get("exit_code") != 0:
        errors.append(f"{code}:EXIT_CODE_NOT_ZERO")
    if receipt.get("result") not in ALLOWED_RESULTS:
        errors.append(f"{code}:RESULT_INVALID")
    if not str(receipt.get("producer") or "").strip():
        errors.append(f"{code}:PRODUCER_MISSING")
    for field in ("code_head_sha", "configuration_sha256", "source_or_fixture_sha256", "evidence_sha256"):
        if not SHA256_RE.fullmatch(str(receipt.get(field) or "")):
            errors.append(f"{code}:{field.upper()}_INVALID")
    evidence = receipt.get("evidence_payload")
    if evidence is None:
        errors.append(f"{code}:EVIDENCE_PAYLOAD_MISSING")
    elif canonical_sha(evidence) != receipt.get("evidence_sha256"):
        errors.append(f"{code}:EVIDENCE_SHA_MISMATCH")
    if receipt.get("test_id") is None:
        errors.append(f"{code}:TEST_ID_MISSING")
    return errors


def ekb_executable_gate(results: Any) -> dict[str, Any]:
    if not isinstance(results, dict):
        return {"result": "BLOCKED", "errors": ["EKB_RESULTS_NOT_OBJECT"], "production_authorized": False}
    missing = sorted(code for code in BINDINGS if code not in results)
    errors: list[str] = []
    errors.extend(f"{code}:MISSING" for code in missing)
    for code in BINDINGS:
        if code in results:
            errors.extend(validate_receipt(code, results[code]))
    if errors:
        return {"result": "BLOCKED", "errors": sorted(set(errors)), "production_authorized": False}
    unresolved = sorted(
        code
        for code, receipt in results.items()
        if receipt.get("result") in {"FAIL", "BLOCKED", "HUMAN_REVIEW_REQUIRED"}
    )
    return {
        "result": "EKB_EXECUTION_VERIFIED_WITH_BLOCKERS" if unresolved else "EKB_EXECUTION_VERIFIED_CLEAR",
        "unresolved": unresolved,
        "receipt_count": len(results),
        "registry_sha256": canonical_sha(BINDINGS),
        "production_authorized": False,
    }


def make_receipt(code: str, result: str = "PASS", evidence: Any | None = None) -> dict[str, Any]:
    evidence = evidence or {"assertions": ["example"], "code": code}
    return {
        "validation_id": BINDINGS[code],
        "test_id": f"TEST-{code}",
        "producer": "self-test",
        "executed": True,
        "exit_code": 0,
        "result": result,
        "code_head_sha": "a" * 64,
        "configuration_sha256": "b" * 64,
        "source_or_fixture_sha256": "c" * 64,
        "evidence_payload": evidence,
        "evidence_sha256": canonical_sha(evidence),
    }


def self_test() -> dict[str, Any]:
    legacy = {code: ("HUMAN_REVIEW_REQUIRED" if code == "EKB-P0-014" else "BLOCKED") for code in BINDINGS}
    legacy_result = ekb_executable_gate(legacy)
    if legacy_result.get("result") != "BLOCKED":
        raise AssertionError("legacy status-only EKB map must be blocked")

    current = {code: make_receipt(code) for code in BINDINGS}
    current["EKB-P0-014"] = make_receipt(
        "EKB-P0-014",
        "BLOCKED",
        {"case": "short phrase grouping", "observed": "real-source grouping defect remains"},
    )
    current["EKB-P0-020"] = make_receipt(
        "EKB-P0-020",
        "BLOCKED",
        {"case": "short OCR materiality", "observed": "real-source decorative false positive remains"},
    )
    current_result = ekb_executable_gate(current)
    if current_result.get("result") != "EKB_EXECUTION_VERIFIED_WITH_BLOCKERS":
        raise AssertionError("executed blockers must remain visible")
    if current_result.get("unresolved") != ["EKB-P0-014", "EKB-P0-020"]:
        raise AssertionError("unexpected unresolved set")

    tampered = json.loads(json.dumps(current))
    tampered["EKB-P0-014"]["evidence_payload"]["observed"] = "tampered"
    tampered_result = ekb_executable_gate(tampered)
    if tampered_result.get("result") != "BLOCKED" or "EKB-P0-014:EVIDENCE_SHA_MISMATCH" not in tampered_result.get("errors", []):
        raise AssertionError("tampered receipt must be blocked")

    return {
        "result": "PASS",
        "legacy_status_only_blocked": True,
        "executed_blockers_visible": current_result["unresolved"],
        "tampered_receipt_blocked": True,
        "production_authorized": False,
    }


if __name__ == "__main__":
    print(json.dumps(self_test(), sort_keys=True))
