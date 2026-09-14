#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import PurePosixPath
from typing import Any, Iterable

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
OP_CODE = re.compile(r"^[A-Z0-9_]+$")
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

PASS_RESULTS = {
    "PASS_REPOSITORY_CHANGE_WITH_READBACK",
    "NOOP_IDEMPOTENT_ALREADY_APPLIED",
}
UNKNOWN_RESULT = "RECONCILIATION_REQUIRED_UNKNOWN_OUTCOME"


def canonical_request_material(request: dict[str, Any]) -> bytes:
    payload = {k: v for k, v in request.items() if k != "request_sha256"}
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def request_sha256(request: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_request_material(request)).hexdigest()


def _safe_path(value: Any, *, allow_prefix: bool = False) -> bool:
    if not isinstance(value, str) or not value or "\\" in value or value.startswith("/"):
        return False
    raw = value
    if allow_prefix and raw.endswith("/**"):
        raw = raw[:-3]
    if not raw or "*" in raw:
        return False
    p = PurePosixPath(raw)
    if any(part in {"", ".", ".."} for part in p.parts):
        return False
    if p.parts and p.parts[0] == ".git":
        return False
    return str(p) == raw.rstrip("/")


def _matches_scope(path: str, allowed: str) -> bool:
    if allowed.endswith("/**"):
        prefix = allowed[:-3].rstrip("/")
        return path == prefix or path.startswith(prefix + "/")
    return path == allowed


def _all_requested_in_scope(requested: Iterable[str], allowed: Iterable[str]) -> bool:
    allow = list(allowed)
    return all(any(_matches_scope(path, scope) for scope in allow) for path in requested)


def validate_request(request: dict[str, Any], governed_providers: set[str]) -> dict[str, Any]:
    findings: list[str] = []
    required = {
        "request_version", "owner_code", "operation_code", "execution_id",
        "repository_full_name", "target_branch", "expected_head", "allowed_paths",
        "requested_paths", "request_sha256", "idempotency_key",
        "transport_provider_ref", "authority_receipt_ref",
    }
    missing = sorted(required - set(request))
    if missing:
        findings.append("REQUEST_FIELDS_MISSING:" + ",".join(missing))

    if request.get("request_version") != "LF_REPOSITORY_CHANGE_REQUEST_V1":
        findings.append("REQUEST_VERSION_INVALID")
    if not isinstance(request.get("owner_code"), str) or not request.get("owner_code", "").strip():
        findings.append("OWNER_CODE_INVALID")
    if not isinstance(request.get("operation_code"), str) or not OP_CODE.fullmatch(request.get("operation_code", "")):
        findings.append("OPERATION_CODE_INVALID")
    if not isinstance(request.get("execution_id"), str) or not request.get("execution_id", "").strip():
        findings.append("EXECUTION_ID_INVALID")
    if not isinstance(request.get("repository_full_name"), str) or not REPO.fullmatch(request.get("repository_full_name", "")):
        findings.append("REPOSITORY_IDENTITY_INVALID")

    target = request.get("target_branch")
    if not isinstance(target, str) or not target.strip() or target in {"main", "master", "refs/heads/main", "refs/heads/master"}:
        findings.append("TARGET_BRANCH_INVALID_OR_PROTECTED_MAIN")
    if not isinstance(request.get("expected_head"), str) or not HEX40.fullmatch(request.get("expected_head", "")):
        findings.append("EXPECTED_HEAD_INVALID")

    allowed = request.get("allowed_paths")
    requested = request.get("requested_paths")
    if not isinstance(allowed, list) or not allowed or len(allowed) != len(set(allowed or [])) or not all(_safe_path(x, allow_prefix=True) for x in (allowed or [])):
        findings.append("ALLOWED_PATHS_INVALID")
    if not isinstance(requested, list) or not requested or len(requested) != len(set(requested or [])) or not all(_safe_path(x) for x in (requested or [])):
        findings.append("REQUESTED_PATHS_INVALID")
    if isinstance(allowed, list) and isinstance(requested, list) and allowed and requested and not _all_requested_in_scope(requested, allowed):
        findings.append("BLOCK_SCOPE_VIOLATION")

    provider = request.get("transport_provider_ref")
    if not isinstance(provider, str) or provider not in governed_providers:
        findings.append("BLOCK_PROVIDER_NOT_GOVERNED")
    if not isinstance(request.get("authority_receipt_ref"), str) or not request.get("authority_receipt_ref", "").strip():
        findings.append("AUTHORITY_RECEIPT_REF_INVALID")
    if not isinstance(request.get("idempotency_key"), str) or not request.get("idempotency_key", "").strip():
        findings.append("IDEMPOTENCY_KEY_INVALID")

    observed_sha = request.get("request_sha256")
    computed_sha = request_sha256(request)
    if not isinstance(observed_sha, str) or not HEX64.fullmatch(observed_sha) or observed_sha != computed_sha:
        findings.append("BLOCK_REQUEST_IDENTITY_MISMATCH")

    return {
        "status": "PASS" if not findings else "BLOCKED",
        "findings": findings,
        "computed_request_sha256": computed_sha,
    }


def validate_receipt(request: dict[str, Any], receipt: dict[str, Any], governed_providers: set[str]) -> dict[str, Any]:
    pre = validate_request(request, governed_providers)
    findings = list(pre["findings"])
    required = {
        "receipt_version", "result", "owner_code", "operation_code", "execution_id",
        "repository_full_name", "target_branch", "before_head", "after_head",
        "request_sha256", "idempotency_key", "transport_provider_ref",
        "transport_provider_version", "changed_paths", "path_readbacks",
        "remote_head_readback", "merge_authorized",
    }
    missing = sorted(required - set(receipt))
    if missing:
        findings.append("RECEIPT_FIELDS_MISSING:" + ",".join(missing))

    if receipt.get("receipt_version") != "LF_REPOSITORY_CHANGE_RECEIPT_V1":
        findings.append("RECEIPT_VERSION_INVALID")
    if receipt.get("result") not in PASS_RESULTS | {
        "BLOCK_STALE_HEAD", "BLOCK_SCOPE_VIOLATION", "BLOCK_PROVIDER_NOT_GOVERNED",
        "BLOCK_REQUEST_IDENTITY_MISMATCH", "BLOCK_READBACK_MISMATCH", UNKNOWN_RESULT,
    }:
        findings.append("RESULT_VOCABULARY_INVALID")

    exact = {
        "owner_code": request.get("owner_code"),
        "operation_code": request.get("operation_code"),
        "execution_id": request.get("execution_id"),
        "repository_full_name": request.get("repository_full_name"),
        "target_branch": request.get("target_branch"),
        "before_head": request.get("expected_head"),
        "request_sha256": request.get("request_sha256"),
        "idempotency_key": request.get("idempotency_key"),
        "transport_provider_ref": request.get("transport_provider_ref"),
    }
    mismatched = sorted(k for k, expected in exact.items() if receipt.get(k) != expected)
    if mismatched:
        findings.append("RECEIPT_REQUEST_BINDING_MISMATCH:" + ",".join(mismatched))

    if receipt.get("transport_provider_ref") not in governed_providers:
        findings.append("BLOCK_PROVIDER_NOT_GOVERNED")
    if not isinstance(receipt.get("transport_provider_version"), str) or not receipt.get("transport_provider_version", "").strip():
        findings.append("TRANSPORT_PROVIDER_VERSION_INVALID")
    if receipt.get("merge_authorized") is not False:
        findings.append("MERGE_AUTHORITY_MUST_REMAIN_FALSE")

    after = receipt.get("after_head")
    remote = receipt.get("remote_head_readback")
    if not isinstance(after, str) or not HEX40.fullmatch(after):
        findings.append("AFTER_HEAD_INVALID")
    if not isinstance(remote, str) or not HEX40.fullmatch(remote):
        findings.append("REMOTE_HEAD_READBACK_INVALID")
    if isinstance(after, str) and isinstance(remote, str) and after != remote:
        findings.append("BLOCK_READBACK_MISMATCH:REMOTE_HEAD")

    changed = receipt.get("changed_paths")
    readbacks = receipt.get("path_readbacks")
    if not isinstance(changed, list) or len(changed) != len(set(changed or [])) or not all(_safe_path(x) for x in (changed or [])):
        findings.append("CHANGED_PATHS_INVALID")
        changed = []
    if not isinstance(readbacks, list):
        findings.append("PATH_READBACKS_INVALID")
        readbacks = []

    result = receipt.get("result")
    if result == "PASS_REPOSITORY_CHANGE_WITH_READBACK":
        if set(changed) != set(request.get("requested_paths") or []):
            findings.append("BLOCK_READBACK_MISMATCH:CHANGED_PATH_SET")
        if receipt.get("before_head") == receipt.get("after_head"):
            findings.append("PASS_MUTATION_REQUIRES_HEAD_ADVANCE")
        by_path: dict[str, dict[str, Any]] = {}
        for row in readbacks:
            if not isinstance(row, dict) or not _safe_path(row.get("path")):
                findings.append("PATH_READBACK_ROW_INVALID")
                continue
            path = row["path"]
            if path in by_path:
                findings.append("PATH_READBACK_DUPLICATE:" + path)
            by_path[path] = row
            if not HEX40.fullmatch(str(row.get("blob_sha", ""))):
                findings.append("PATH_READBACK_BLOB_INVALID:" + path)
            if not HEX64.fullmatch(str(row.get("sha256", ""))):
                findings.append("PATH_READBACK_SHA256_INVALID:" + path)
        if set(by_path) != set(changed):
            findings.append("BLOCK_READBACK_MISMATCH:PATH_READBACK_SET")
    elif result == "NOOP_IDEMPOTENT_ALREADY_APPLIED":
        if changed or readbacks:
            findings.append("NOOP_MUST_NOT_CLAIM_NEW_CHANGED_PATHS")
        if not isinstance(receipt.get("prior_receipt_ref"), str) or not receipt.get("prior_receipt_ref", "").strip():
            findings.append("NOOP_PRIOR_RECEIPT_REF_REQUIRED")
    elif result == UNKNOWN_RESULT:
        if not isinstance(receipt.get("unknown_outcome_detail"), str) or not receipt.get("unknown_outcome_detail", "").strip():
            findings.append("UNKNOWN_OUTCOME_DETAIL_REQUIRED")

    disposition = "ACCEPT_PASS" if result in PASS_RESULTS and not findings else (
        "RECONCILE_DO_NOT_REDISPATCH" if result == UNKNOWN_RESULT and not findings else "BLOCK"
    )
    return {
        "status": "PASS" if disposition == "ACCEPT_PASS" else ("RECONCILIATION_REQUIRED" if disposition == "RECONCILE_DO_NOT_REDISPATCH" else "BLOCKED"),
        "disposition": disposition,
        "findings": findings,
    }
