#!/usr/bin/env python3
"""Pre-execution authority manifest and deterministic semantic check-bundle builder."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

MANIFEST_SCHEMA = "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1"
BUNDLE_SCHEMA = "PROFILE_SEMANTIC_CHECK_BUNDLE_V2"
AUTHORITY_TYPES = {
    "PROFILE_CONTRACT",
    "EXECUTION_INPUT",
    "DECISION_SET",
    "UPSTREAM_CONSTRAINTS",
}
CHECK_TYPES = {
    "REQUIRED_SUBSTRING",
    "FORBIDDEN_SUBSTRING",
    "EXACT_VALUE",
    "SEMANTIC_RELATION",
}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
OBLIGATION_ID_RE = re.compile(r"^[A-Z0-9][A-Z0-9_.:-]{0,127}$")
POINTER_RE = re.compile(r"^(?:\$|(?:/(?:[^~/]|~0|~1)*)+)$")


class ObligationManifestError(ValueError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def canonical_json_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def _text(value: Any, name: str, *, max_len: int = 6000) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ObligationManifestError(f"{name}_REQUIRED")
    out = value.strip()
    if len(out) > max_len:
        raise ObligationManifestError(f"{name}_TOO_LONG")
    return out


def _sha(value: Any, name: str) -> str:
    if not isinstance(value, str) or not HEX64.fullmatch(value):
        raise ObligationManifestError(f"{name}_INVALID")
    return value


def _ids(value: Any, name: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or len(value) > 64 or (not value and not allow_empty):
        raise ObligationManifestError(f"{name}_INVALID")
    out: list[str] = []
    seen: set[str] = set()
    for raw in value:
        item = _text(raw, name, max_len=128)
        if not OBLIGATION_ID_RE.fullmatch(item):
            raise ObligationManifestError(f"{name}_FORMAT_INVALID")
        if item in seen:
            raise ObligationManifestError(f"{name}_DUPLICATE")
        seen.add(item)
        out.append(item)
    return out


def validate_obligation_manifest(
    manifest: Any,
    *,
    expected_execution_id: str | None = None,
    expected_profile_code: str | None = None,
    expected_profile_source_sha256: str | None = None,
    expected_input_sha256: str | None = None,
) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        raise ObligationManifestError("MANIFEST_NOT_OBJECT")
    if manifest.get("schema") != MANIFEST_SCHEMA:
        raise ObligationManifestError("MANIFEST_SCHEMA_INVALID")

    execution_id = _text(manifest.get("execution_id"), "EXECUTION_ID", max_len=256)
    profile_code = _text(manifest.get("profile_code"), "PROFILE_CODE", max_len=256)
    profile_source_sha = _sha(manifest.get("profile_source_sha256"), "PROFILE_SOURCE_SHA256")
    input_sha = _sha(manifest.get("input_sha256"), "INPUT_SHA256")

    if expected_execution_id is not None and execution_id != expected_execution_id:
        raise ObligationManifestError("EXECUTION_ID_MISMATCH")
    if expected_profile_code is not None and profile_code != expected_profile_code:
        raise ObligationManifestError("PROFILE_CODE_MISMATCH")
    if expected_profile_source_sha256 is not None and profile_source_sha != expected_profile_source_sha256:
        raise ObligationManifestError("PROFILE_SOURCE_SHA256_MISMATCH")
    if expected_input_sha256 is not None and input_sha != expected_input_sha256:
        raise ObligationManifestError("INPUT_SHA256_MISMATCH")

    authorities = manifest.get("authority_sources")
    if not isinstance(authorities, list) or not 2 <= len(authorities) <= 16:
        raise ObligationManifestError("AUTHORITY_SOURCES_INVALID")
    normalized_authorities: list[dict[str, Any]] = []
    authority_by_id: dict[str, dict[str, Any]] = {}
    authority_types: set[str] = set()
    required_by_authority: dict[str, set[str]] = {}
    for index, raw in enumerate(authorities):
        if not isinstance(raw, dict):
            raise ObligationManifestError(f"AUTHORITY_{index}_NOT_OBJECT")
        authority_id = _text(raw.get("authority_id"), f"AUTHORITY_{index}_ID", max_len=128)
        if authority_id in authority_by_id:
            raise ObligationManifestError("AUTHORITY_ID_DUPLICATE")
        authority_type = raw.get("authority_type")
        if authority_type not in AUTHORITY_TYPES:
            raise ObligationManifestError(f"AUTHORITY_{authority_id}_TYPE_INVALID")
        source_ref = _text(raw.get("source_ref"), f"AUTHORITY_{authority_id}_SOURCE_REF", max_len=1000)
        source_sha = _sha(raw.get("source_sha256"), f"AUTHORITY_{authority_id}_SOURCE_SHA256")
        required_ids = _ids(
            raw.get("required_obligation_ids"),
            f"AUTHORITY_{authority_id}_REQUIRED_IDS",
            allow_empty=True,
        )
        if authority_type == "PROFILE_CONTRACT" and source_sha != profile_source_sha:
            raise ObligationManifestError("PROFILE_CONTRACT_AUTHORITY_SHA_MISMATCH")
        if authority_type == "EXECUTION_INPUT" and source_sha != input_sha:
            raise ObligationManifestError("EXECUTION_INPUT_AUTHORITY_SHA_MISMATCH")
        normalized = {
            "authority_id": authority_id,
            "authority_type": authority_type,
            "source_ref": source_ref,
            "source_sha256": source_sha,
            "required_obligation_ids": required_ids,
        }
        authority_by_id[authority_id] = normalized
        authority_types.add(authority_type)
        required_by_authority[authority_id] = set(required_ids)
        normalized_authorities.append(normalized)

    missing_types = {"PROFILE_CONTRACT", "EXECUTION_INPUT"} - authority_types
    if missing_types:
        raise ObligationManifestError("MANDATORY_AUTHORITY_TYPE_MISSING:" + ",".join(sorted(missing_types)))

    obligations = manifest.get("obligations")
    if not isinstance(obligations, list) or not 1 <= len(obligations) <= 64:
        raise ObligationManifestError("OBLIGATIONS_INVALID")
    normalized_obligations: list[dict[str, Any]] = []
    obligation_ids: set[str] = set()
    for index, raw in enumerate(obligations):
        if not isinstance(raw, dict):
            raise ObligationManifestError(f"OBLIGATION_{index}_NOT_OBJECT")
        obligation_id = _text(raw.get("obligation_id"), f"OBLIGATION_{index}_ID", max_len=128)
        if not OBLIGATION_ID_RE.fullmatch(obligation_id):
            raise ObligationManifestError(f"OBLIGATION_{index}_ID_FORMAT_INVALID")
        if obligation_id in obligation_ids:
            raise ObligationManifestError("OBLIGATION_ID_DUPLICATE")
        obligation_ids.add(obligation_id)
        rule = _text(raw.get("rule"), f"OBLIGATION_{obligation_id}_RULE")
        check_type = raw.get("check_type")
        if check_type not in CHECK_TYPES:
            raise ObligationManifestError(f"OBLIGATION_{obligation_id}_CHECK_TYPE_INVALID")
        evidence_pointer = _text(raw.get("evidence_pointer"), f"OBLIGATION_{obligation_id}_EVIDENCE_POINTER", max_len=1000)
        if not POINTER_RE.fullmatch(evidence_pointer):
            raise ObligationManifestError(f"OBLIGATION_{obligation_id}_EVIDENCE_POINTER_INVALID")
        authority_ids = _ids(raw.get("authority_ids"), f"OBLIGATION_{obligation_id}_AUTHORITY_IDS")
        unknown = set(authority_ids) - set(authority_by_id)
        if unknown:
            raise ObligationManifestError(f"OBLIGATION_{obligation_id}_AUTHORITY_UNKNOWN")
        declared_by = {aid for aid, ids in required_by_authority.items() if obligation_id in ids}
        if set(authority_ids) != declared_by:
            raise ObligationManifestError(f"OBLIGATION_{obligation_id}_AUTHORITY_COVERAGE_MISMATCH")

        out: dict[str, Any] = {
            "obligation_id": obligation_id,
            "rule": rule,
            "check_type": check_type,
            "evidence_pointer": evidence_pointer,
            "authority_ids": authority_ids,
        }
        if check_type == "REQUIRED_SUBSTRING":
            out["expected"] = [_text(x, f"OBLIGATION_{obligation_id}_EXPECTED", max_len=1000) for x in raw.get("expected", [])]
            if not out["expected"]:
                raise ObligationManifestError(f"OBLIGATION_{obligation_id}_EXPECTED_INVALID")
        elif check_type == "FORBIDDEN_SUBSTRING":
            out["forbidden"] = [_text(x, f"OBLIGATION_{obligation_id}_FORBIDDEN", max_len=1000) for x in raw.get("forbidden", [])]
            if not out["forbidden"]:
                raise ObligationManifestError(f"OBLIGATION_{obligation_id}_FORBIDDEN_INVALID")
        elif check_type == "EXACT_VALUE":
            out["expected_value"] = _text(raw.get("expected_value"), f"OBLIGATION_{obligation_id}_EXPECTED_VALUE", max_len=4000)
        else:
            out["question"] = _text(
                raw.get("question") or "Does the evidence comply with the rule, contradict it, or remain uncertain?",
                f"OBLIGATION_{obligation_id}_QUESTION",
                max_len=1500,
            )
        normalized_obligations.append(out)

    required_union: set[str] = set()
    for ids in required_by_authority.values():
        required_union.update(ids)
    if required_union != obligation_ids:
        raise ObligationManifestError("REQUIRED_OBLIGATION_SET_MISMATCH")

    normalized_authorities.sort(key=lambda item: item["authority_id"])
    normalized_obligations.sort(key=lambda item: item["obligation_id"])
    return {
        "schema": MANIFEST_SCHEMA,
        "execution_id": execution_id,
        "profile_code": profile_code,
        "profile_source_sha256": profile_source_sha,
        "input_sha256": input_sha,
        "authority_sources": normalized_authorities,
        "obligations": normalized_obligations,
    }


def obligation_manifest_sha256(manifest: Any, **expected: Any) -> str:
    return canonical_json_sha256(validate_obligation_manifest(manifest, **expected))


def _json_pointer_get(value: Any, pointer: str) -> Any:
    if pointer == "$":
        return value
    current = value
    for encoded in pointer.split("/")[1:]:
        token = encoded.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict):
            if token not in current:
                raise ObligationManifestError("EVIDENCE_POINTER_NOT_FOUND:" + pointer)
            current = current[token]
        elif isinstance(current, list):
            if not token.isdigit():
                raise ObligationManifestError("EVIDENCE_POINTER_INDEX_INVALID:" + pointer)
            index = int(token)
            if index >= len(current):
                raise ObligationManifestError("EVIDENCE_POINTER_INDEX_RANGE:" + pointer)
            current = current[index]
        else:
            raise ObligationManifestError("EVIDENCE_POINTER_TRAVERSAL_INVALID:" + pointer)
    return current


def _evidence_text(value: Any) -> str:
    if isinstance(value, str):
        text = value
    else:
        text = canonical_json(value)
    if not text.strip():
        raise ObligationManifestError("EVIDENCE_EMPTY")
    if len(text) > 6000:
        raise ObligationManifestError("EVIDENCE_TOO_LONG")
    return text


def build_check_bundle(manifest: Any, raw_output: Any, *, raw_output_sha256: str) -> dict[str, Any]:
    normalized = validate_obligation_manifest(manifest)
    raw_sha = _sha(raw_output_sha256, "RAW_OUTPUT_SHA256")
    observed_raw_sha = canonical_json_sha256(raw_output)
    if observed_raw_sha != raw_sha:
        raise ObligationManifestError("RAW_OUTPUT_SHA256_MISMATCH")

    authority_ref_by_id = {
        item["authority_id"]: item["source_ref"] for item in normalized["authority_sources"]
    }
    checks: list[dict[str, Any]] = []
    for obligation in normalized["obligations"]:
        evidence = _evidence_text(_json_pointer_get(raw_output, obligation["evidence_pointer"]))
        check: dict[str, Any] = {
            "check_id": obligation["obligation_id"],
            "obligation_id": obligation["obligation_id"],
            "check_type": obligation["check_type"],
            "rule": obligation["rule"],
            "evidence": evidence,
            "source_refs": [authority_ref_by_id[aid] for aid in obligation["authority_ids"]],
        }
        for key in ("expected", "forbidden", "expected_value", "question"):
            if key in obligation:
                check[key] = obligation[key]
        if obligation["check_type"] == "EXACT_VALUE":
            check["observed_value"] = evidence
        checks.append(check)

    return {
        "schema": BUNDLE_SCHEMA,
        "execution_id": normalized["execution_id"],
        "profile_code": normalized["profile_code"],
        "input_sha256": normalized["input_sha256"],
        "raw_output_sha256": raw_sha,
        "obligation_manifest_sha256": canonical_json_sha256(normalized),
        "checks": checks,
    }
