#!/usr/bin/env python3
"""Deterministic front gate and receipt builder for the narrow semantic mini-judge."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from typing import Any, Iterable

from semantic_obligation_manifest import BUNDLE_SCHEMA, CHECK_TYPES

RECEIPT_TYPE = "PROFILE_SEMANTIC_JUDGE_RECEIPT_V2"
MODEL_VERDICTS = {"COMPLIES", "CONTRADICTS", "UNCERTAIN"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class MiniJudgeInputError(ValueError):
    pass


@dataclass(frozen=True)
class CheckResult:
    check_id: str
    verdict: str
    reason_code: str
    decided_by: str
    model_evidence: dict[str, Any] | None = None

    def as_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "check_id": self.check_id,
            "verdict": self.verdict,
            "reason_code": self.reason_code,
            "decided_by": self.decided_by,
        }
        if self.model_evidence is not None:
            payload["model_evidence"] = self.model_evidence
        return payload


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def canonical_json_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _required_text(value: Any, name: str, *, max_len: int = 12000) -> str:
    if not isinstance(value, str) or not value.strip():
        raise MiniJudgeInputError(f"{name}_REQUIRED")
    value = value.strip()
    if len(value) > max_len:
        raise MiniJudgeInputError(f"{name}_TOO_LONG")
    return value


def _string_list(value: Any, name: str, *, min_items: int = 1, max_items: int = 32) -> list[str]:
    if not isinstance(value, list) or not (min_items <= len(value) <= max_items):
        raise MiniJudgeInputError(f"{name}_INVALID")
    out: list[str] = []
    for item in value:
        out.append(_required_text(item, name, max_len=1000))
    return out


def validate_bundle(bundle: Any) -> dict[str, Any]:
    if not isinstance(bundle, dict):
        raise MiniJudgeInputError("BUNDLE_NOT_OBJECT")
    if bundle.get("schema") != BUNDLE_SCHEMA:
        raise MiniJudgeInputError("BUNDLE_SCHEMA_INVALID")
    execution_id = _required_text(bundle.get("execution_id"), "EXECUTION_ID", max_len=256)
    profile_code = _required_text(bundle.get("profile_code"), "PROFILE_CODE", max_len=256)
    input_sha = bundle.get("input_sha256")
    raw_sha = bundle.get("raw_output_sha256")
    manifest_sha = bundle.get("obligation_manifest_sha256")
    for value, name in (
        (input_sha, "INPUT_SHA256"),
        (raw_sha, "RAW_OUTPUT_SHA256"),
        (manifest_sha, "OBLIGATION_MANIFEST_SHA256"),
    ):
        if not isinstance(value, str) or not HEX64.fullmatch(value):
            raise MiniJudgeInputError(f"{name}_INVALID")
    checks = bundle.get("checks")
    if not isinstance(checks, list) or not 1 <= len(checks) <= 64:
        raise MiniJudgeInputError("CHECKS_INVALID")

    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, item in enumerate(checks):
        if not isinstance(item, dict):
            raise MiniJudgeInputError(f"CHECK_{index}_NOT_OBJECT")
        check_id = _required_text(item.get("check_id"), f"CHECK_{index}_ID", max_len=128)
        obligation_id = _required_text(item.get("obligation_id"), f"CHECK_{index}_OBLIGATION_ID", max_len=128)
        if check_id != obligation_id:
            raise MiniJudgeInputError("CHECK_ID_OBLIGATION_ID_MISMATCH")
        if check_id in seen:
            raise MiniJudgeInputError("CHECK_ID_DUPLICATE")
        seen.add(check_id)
        check_type = item.get("check_type")
        if check_type not in CHECK_TYPES:
            raise MiniJudgeInputError(f"CHECK_{check_id}_TYPE_INVALID")
        rule = _required_text(item.get("rule"), f"CHECK_{check_id}_RULE", max_len=6000)
        evidence = _required_text(item.get("evidence"), f"CHECK_{check_id}_EVIDENCE", max_len=6000)
        source_refs = item.get("source_refs", [])
        if source_refs != []:
            source_refs = _string_list(source_refs, f"CHECK_{check_id}_SOURCE_REFS", min_items=1, max_items=16)

        out: dict[str, Any] = {
            "check_id": check_id,
            "obligation_id": obligation_id,
            "check_type": check_type,
            "rule": rule,
            "evidence": evidence,
            "source_refs": source_refs,
        }
        if check_type == "REQUIRED_SUBSTRING":
            out["expected"] = _string_list(item.get("expected"), f"CHECK_{check_id}_EXPECTED")
        elif check_type == "FORBIDDEN_SUBSTRING":
            out["forbidden"] = _string_list(item.get("forbidden"), f"CHECK_{check_id}_FORBIDDEN")
        elif check_type == "EXACT_VALUE":
            out["expected_value"] = _required_text(item.get("expected_value"), f"CHECK_{check_id}_EXPECTED_VALUE", max_len=4000)
            out["observed_value"] = _required_text(item.get("observed_value"), f"CHECK_{check_id}_OBSERVED_VALUE", max_len=4000)
        else:
            question = item.get("question") or "Does the evidence comply with the rule, contradict it, or remain uncertain?"
            out["question"] = _required_text(question, f"CHECK_{check_id}_QUESTION", max_len=1500)
        normalized.append(out)

    return {
        "schema": BUNDLE_SCHEMA,
        "execution_id": execution_id,
        "profile_code": profile_code,
        "input_sha256": input_sha,
        "raw_output_sha256": raw_sha,
        "obligation_manifest_sha256": manifest_sha,
        "checks": normalized,
    }


def _fold(value: str) -> str:
    return " ".join(value.casefold().split())


def evaluate_deterministic(check: dict[str, Any]) -> CheckResult | None:
    check_id = check["check_id"]
    check_type = check["check_type"]
    evidence = _fold(check["evidence"])
    if check_type == "REQUIRED_SUBSTRING":
        missing = [term for term in check["expected"] if _fold(term) not in evidence]
        if missing:
            return CheckResult(check_id, "CONTRADICTS", "REQUIRED_TEXT_MISSING", "PYTHON_DETERMINISTIC")
        return CheckResult(check_id, "COMPLIES", "REQUIRED_TEXT_PRESENT", "PYTHON_DETERMINISTIC")
    if check_type == "FORBIDDEN_SUBSTRING":
        present = [term for term in check["forbidden"] if _fold(term) in evidence]
        if present:
            return CheckResult(check_id, "CONTRADICTS", "FORBIDDEN_TEXT_PRESENT", "PYTHON_DETERMINISTIC")
        return CheckResult(check_id, "COMPLIES", "FORBIDDEN_TEXT_ABSENT", "PYTHON_DETERMINISTIC")
    if check_type == "EXACT_VALUE":
        if check["observed_value"].strip() == check["expected_value"].strip():
            return CheckResult(check_id, "COMPLIES", "EXACT_VALUE_MATCH", "PYTHON_DETERMINISTIC")
        return CheckResult(check_id, "CONTRADICTS", "EXACT_VALUE_MISMATCH", "PYTHON_DETERMINISTIC")
    return None


def partition_checks(bundle: dict[str, Any]) -> tuple[list[CheckResult], list[dict[str, Any]]]:
    deterministic: list[CheckResult] = []
    semantic: list[dict[str, Any]] = []
    for check in bundle["checks"]:
        resolved = evaluate_deterministic(check)
        if resolved is None:
            semantic.append(check)
        else:
            deterministic.append(resolved)
    return deterministic, semantic


def compact_semantic_payload(check: dict[str, Any]) -> dict[str, str]:
    if check["check_type"] != "SEMANTIC_RELATION":
        raise MiniJudgeInputError("SEMANTIC_PAYLOAD_TYPE_INVALID")
    return {
        "check_id": check["check_id"],
        "rule": check["rule"],
        "evidence": check["evidence"],
        "question": check["question"],
    }


def parse_model_response(raw_text: str, *, check_id: str) -> CheckResult:
    text = raw_text.strip()
    if text.startswith("```") and text.endswith("```"):
        lines = text.splitlines()
        if len(lines) >= 3:
            text = "\n".join(lines[1:-1]).strip()
            if text.startswith("json\n"):
                text = text[5:].strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return CheckResult(check_id, "UNCERTAIN", "MODEL_OUTPUT_NOT_JSON", "LOCAL_SEMANTIC_MODEL")
    if not isinstance(data, dict):
        return CheckResult(check_id, "UNCERTAIN", "MODEL_OUTPUT_NOT_OBJECT", "LOCAL_SEMANTIC_MODEL")
    verdict = data.get("verdict")
    reason_code = data.get("reason_code")
    if verdict not in MODEL_VERDICTS:
        return CheckResult(check_id, "UNCERTAIN", "MODEL_VERDICT_INVALID", "LOCAL_SEMANTIC_MODEL")
    if not isinstance(reason_code, str) or not reason_code.strip() or len(reason_code) > 128:
        reason_code = "MODEL_REASON_INVALID"
        verdict = "UNCERTAIN"
    return CheckResult(check_id, verdict, reason_code.strip(), "LOCAL_SEMANTIC_MODEL")


def aggregate_verdict(results: Iterable[CheckResult]) -> tuple[str, str]:
    values = list(results)
    if not values:
        return "UNCERTAIN", "BLOCK"
    if any(result.verdict == "CONTRADICTS" for result in values):
        return "FAIL", "BLOCK"
    if any(result.verdict == "UNCERTAIN" for result in values):
        return "UNCERTAIN", "BLOCK"
    if all(result.verdict == "COMPLIES" for result in values):
        return "PASS", "ELIGIBLE"
    return "UNCERTAIN", "BLOCK"


def build_receipt(bundle: dict[str, Any], results: list[CheckResult], *, runtime_evidence: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    verdict, downstream = aggregate_verdict(results)
    payload: dict[str, Any] = {
        "receipt_type": RECEIPT_TYPE,
        "execution_id": bundle["execution_id"],
        "profile_code": bundle["profile_code"],
        "input_sha256": bundle["input_sha256"],
        "raw_output_sha256": bundle["raw_output_sha256"],
        "obligation_manifest_sha256": bundle["obligation_manifest_sha256"],
        "check_bundle_sha256": canonical_json_sha256(bundle),
        "verdict": verdict,
        "downstream_disposition": downstream,
        "uncertain_blocks": True,
        "self_authorizes_downstream": False,
        "checks": [result.as_dict() for result in results],
        "runtime_evidence": runtime_evidence or [],
    }
    payload["receipt_sha256"] = canonical_json_sha256(payload)
    return payload
