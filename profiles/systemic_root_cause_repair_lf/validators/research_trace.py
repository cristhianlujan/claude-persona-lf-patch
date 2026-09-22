"""Canonical SRCR live-research trace validation.

One implementation owns query-trace shape, resolver identity and exact
trace->evidence binding for both GPT-native evaluation and runtime external
resolver mode. This module never performs reads or writes itself.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any

REQUIRED_TOOL_PERMISSIONS = {"READ_GITHUB", "READ_SUPABASE"}
FORBIDDEN_WRITE_PREFIXES = ("WRITE_", "MUTATE_", "DELETE_", "MERGE_", "PUBLISH_", "DEPLOY_")
EVIDENCE_RESOLVERS = {
    "GITHUB": {"resolver_id": "LF_GITHUB_SOURCE_READBACK_V1", "provider": "GITHUB"},
    "SUPABASE": {"resolver_id": "LF_SUPABASE_READBACK_V1", "provider": "SUPABASE"},
}
TRACE_REQUIRED_FIELDS = {
    "sequence",
    "tool_permission",
    "resolver_id",
    "provider",
    "query_locator",
    "request_digest",
    "result_digest",
    "observed_at",
    "evidence_id",
    "consumer",
}


def _sha_ok(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    raw = value.removeprefix("sha256:")
    return len(raw) == 64 and all(ch in "0123456789abcdef" for ch in raw)


def _canonical_sha256(value: Any) -> str:
    raw = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def validate_query_trace(trace: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(trace, list) or not trace:
        return ["QUERY_TRACE_REQUIRED"]

    expected_seq = 1
    seen_evidence: set[str] = set()
    allowed_resolver_ids = {
        item["resolver_id"] for item in EVIDENCE_RESOLVERS.values()
    }

    for idx, row in enumerate(trace):
        path = f"trace[{idx}]"
        if not isinstance(row, dict):
            errors.append(f"{path}:NOT_OBJECT")
            continue
        missing = sorted(TRACE_REQUIRED_FIELDS - set(row))
        if missing:
            errors.append(f"{path}:MISSING:{','.join(missing)}")
            continue
        if row.get("sequence") != expected_seq:
            errors.append(f"{path}:SEQUENCE_MISMATCH")
        expected_seq += 1

        tool = row.get("tool_permission")
        if tool not in REQUIRED_TOOL_PERMISSIONS:
            errors.append(f"{path}:TOOL_PERMISSION_INVALID")
        if isinstance(tool, str) and tool.startswith(FORBIDDEN_WRITE_PREFIXES):
            errors.append(f"{path}:WRITE_TOOL_FORBIDDEN")

        resolver_id = row.get("resolver_id")
        provider = row.get("provider")
        if resolver_id not in allowed_resolver_ids:
            errors.append(f"{path}:RESOLVER_NOT_CANONICAL")
        else:
            expected_provider = next(
                item["provider"]
                for item in EVIDENCE_RESOLVERS.values()
                if item["resolver_id"] == resolver_id
            )
            if provider != expected_provider:
                errors.append(f"{path}:RESOLVER_PROVIDER_MISMATCH")

        locator = row.get("query_locator")
        if not isinstance(locator, str) or not locator.strip():
            errors.append(f"{path}:QUERY_LOCATOR_REQUIRED")
        if not _sha_ok(row.get("request_digest")):
            errors.append(f"{path}:REQUEST_DIGEST_INVALID")
        if not _sha_ok(row.get("result_digest")):
            errors.append(f"{path}:RESULT_DIGEST_INVALID")

        result_status = row.get("result_status")
        result_count = row.get("result_count")
        if result_status is not None:
            if result_status not in {
                "FOUND", "EMPTY", "NOT_FOUND", "UNREACHABLE", "ACCESS_DENIED", "ERROR"
            }:
                errors.append(f"{path}:RESULT_STATUS_INVALID")
            if not isinstance(result_count, int) or result_count < 0:
                errors.append(f"{path}:RESULT_COUNT_INVALID")
            elif result_status == "FOUND" and result_count == 0:
                errors.append(f"{path}:FOUND_WITH_ZERO_RESULTS")
            elif result_status in {"EMPTY", "NOT_FOUND"} and result_count != 0:
                errors.append(f"{path}:ABSENCE_WITH_NONZERO_RESULTS")

        evidence_id = row.get("evidence_id")
        if not isinstance(evidence_id, str) or len(evidence_id.strip()) < 3:
            errors.append(f"{path}:EVIDENCE_ID_INVALID")
        elif evidence_id in seen_evidence:
            errors.append(f"{path}:EVIDENCE_ID_DUPLICATE")
        else:
            seen_evidence.add(evidence_id)

        if not isinstance(row.get("consumer"), str) or not row["consumer"].strip():
            errors.append(f"{path}:CONSUMER_REQUIRED")

    return sorted(set(errors))


def validate_manifest_trace_binding(manifest: Any, trace: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(manifest, dict):
        return ["EVIDENCE_MANIFEST_REQUIRED"]
    if not isinstance(trace, list):
        return ["QUERY_TRACE_REQUIRED"]

    evidence_rows = manifest.get("evidence")
    if not isinstance(evidence_rows, list) or not evidence_rows:
        return ["EVIDENCE_MANIFEST_EVIDENCE_REQUIRED"]

    ids = [
        row.get("evidence_id")
        for row in evidence_rows
        if isinstance(row, dict) and isinstance(row.get("evidence_id"), str)
    ]
    if len(ids) != len(evidence_rows) or len(ids) != len(set(ids)):
        errors.append("EVIDENCE_MANIFEST_IDS_INVALID")
    by_id = {
        row["evidence_id"]: row
        for row in evidence_rows
        if isinstance(row, dict) and isinstance(row.get("evidence_id"), str)
    }

    traced_ids: set[str] = set()
    for idx, row in enumerate(trace):
        if not isinstance(row, dict):
            continue
        evidence_id = row.get("evidence_id")
        evidence = by_id.get(evidence_id)
        if evidence is None:
            errors.append(f"trace[{idx}]:EVIDENCE_NOT_IN_MANIFEST")
            continue
        traced_ids.add(str(evidence_id))
        if evidence.get("source_locator") != row.get("query_locator"):
            errors.append(f"trace[{idx}]:EVIDENCE_LOCATOR_MISMATCH")
        if evidence.get("digest") != row.get("result_digest"):
            errors.append(f"trace[{idx}]:EVIDENCE_DIGEST_MISMATCH")
        provider = row.get("provider")
        locator = str(row.get("query_locator") or "").lower()
        if provider == "GITHUB" and not (
            locator.startswith("github://")
            or locator.startswith("https://api.github.com/")
            or locator.startswith("git:")
        ):
            errors.append(f"trace[{idx}]:GITHUB_LOCATOR_CLASS_MISMATCH")
        if provider == "SUPABASE" and not (
            locator.startswith("supabase://") or locator.startswith("sql:")
        ):
            errors.append(f"trace[{idx}]:SUPABASE_LOCATOR_CLASS_MISMATCH")

    missing = sorted(set(by_id) - traced_ids)
    if missing:
        errors.append("EVIDENCE_WITHOUT_RECORDED_RETRIEVAL:" + ",".join(missing))
    return sorted(set(errors))


def validate_runtime_research_bundle(
    evidence_manifest: Any,
    *,
    resolved_authority_context: Any,
    expected_manifest_sha256: str,
) -> dict[str, Any]:
    trace = evidence_manifest.get("query_trace") if isinstance(evidence_manifest, dict) else None
    errors = validate_query_trace(trace)
    errors.extend(validate_manifest_trace_binding(evidence_manifest, trace))
    if not isinstance(resolved_authority_context, dict) or not resolved_authority_context:
        errors.append("RESOLVED_AUTHORITY_CONTEXT_REQUIRED")

    observed_manifest_sha256 = (
        "sha256:" + _canonical_sha256(evidence_manifest)
        if isinstance(evidence_manifest, dict)
        else None
    )
    if observed_manifest_sha256 != expected_manifest_sha256:
        errors.append("RESOLVED_AUTHORITY_MANIFEST_DIGEST_MISMATCH")

    codes = sorted(set(errors))
    evidence_rows = (
        evidence_manifest.get("evidence")
        if isinstance(evidence_manifest, dict) and isinstance(evidence_manifest.get("evidence"), list)
        else []
    )
    return {
        "status": "PASS" if not codes else "FAIL",
        "blocking_codes": codes,
        "readback": {
            "evidence_manifest_sha256": observed_manifest_sha256,
            "query_count": len(trace) if isinstance(trace, list) else 0,
            "evidence_count": len(evidence_rows),
            "resolved_authority_context_sha256": (
                _canonical_sha256(resolved_authority_context)
                if isinstance(resolved_authority_context, dict) and resolved_authority_context
                else None
            ),
        },
    }
