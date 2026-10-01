#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
CAPABILITY_CODE = "GITHUB_RECONCILIATION"
ENTRY_ACCEPTED = "ORCHESTRATOR_ENTRY_ACCEPTED"


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def _receipt(decision: str, ready: bool, reason: str, *, request: dict[str, Any], scope: dict[str, Any], failures: list[dict[str, Any]], observed_paths: list[str]) -> dict[str, Any]:
    out = {
        "schema_version": "LF_GITHUB_RECONCILIATION_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "decision": decision,
        "ready": ready,
        "reason": reason,
        "plan_digest": request.get("plan_digest"),
        "scope_digest": scope.get("scope_digest"),
        "repository": scope.get("repository"),
        "target_branch": scope.get("target_branch"),
        "expected_merge_commit_sha": scope.get("expected_merge_commit_sha"),
        "declared_path_count": len(scope.get("declared_paths") or []),
        "observed_paths": sorted(observed_paths),
        "failures": failures,
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out


def scope_digest(scope: dict[str, Any]) -> str:
    material = {k: v for k, v in scope.items() if k != "scope_digest"}
    return canonical_sha256(material)


def _validate_request(request: dict[str, Any]) -> str | None:
    if request.get("capability_code") != CAPABILITY_CODE:
        return "CAPABILITY_CODE_MISMATCH"
    entry = request.get("entry_guard_readback")
    if not isinstance(entry, dict) or entry.get("decision") != ENTRY_ACCEPTED:
        return "ORCHESTRATOR_ENTRY_REQUIRED"
    for field in ("orchestrator_execution_id", "consumer_execution_id", "plan_digest", "dispatch_receipt_id", "request_digest", "source_revision"):
        if not isinstance(request.get(field), str) or not request[field]:
            return f"REQUEST_FIELD_MISSING:{field}"
    return None


def _validate_scope(scope: dict[str, Any], request: dict[str, Any]) -> str | None:
    if scope.get("schema_version") != "LF_GITHUB_RECONCILIATION_SCOPE_V1":
        return "SCOPE_SCHEMA_MISMATCH"
    if not isinstance(scope.get("repository"), str) or "/" not in scope["repository"]:
        return "SCOPE_REPOSITORY_INVALID"
    if scope.get("target_branch") != "main":
        return "SCOPE_TARGET_BRANCH_INVALID"
    if not HEX40.fullmatch(scope.get("expected_merge_commit_sha") or ""):
        return "SCOPE_MERGE_SHA_INVALID"
    if request.get("source_revision") != scope.get("expected_merge_commit_sha"):
        return "REQUEST_SOURCE_REVISION_MISMATCH"
    if request.get("plan_digest") != scope.get("plan_digest"):
        return "REQUEST_PLAN_DIGEST_MISMATCH"
    if scope.get("scope_digest") != scope_digest(scope):
        return "SCOPE_DIGEST_MISMATCH"
    paths = scope.get("declared_paths")
    if not isinstance(paths, list) or not paths:
        return "DECLARED_PATHS_REQUIRED"
    names: list[str] = []
    for item in paths:
        if not isinstance(item, dict):
            return "DECLARED_PATH_INVALID"
        path = item.get("path")
        if not isinstance(path, str) or not path or path.startswith("/") or ".." in path:
            return "DECLARED_PATH_INVALID"
        if item.get("kind") not in {"CHANGED", "ANCHOR"}:
            return "DECLARED_PATH_KIND_INVALID"
        if not HEX64.fullmatch(item.get("expected_sha256") or "") or not HEX40.fullmatch(item.get("expected_git_blob") or ""):
            return "DECLARED_PATH_DIGEST_INVALID"
        names.append(path)
    if len(names) != len(set(names)):
        return "DECLARED_PATH_DUPLICATE"
    return None


def evaluate_github_reconciliation(*, request: dict[str, Any], scope: dict[str, Any], observation: dict[str, Any]) -> dict[str, Any]:
    err = _validate_request(request)
    if err:
        return _receipt("RECONCILIATION_FAILED", False, err, request=request, scope=scope, failures=[{"reason": err}], observed_paths=[])
    err = _validate_scope(scope, request)
    if err:
        return _receipt("RECONCILIATION_FAILED", False, err, request=request, scope=scope, failures=[{"reason": err}], observed_paths=[])

    failures: list[dict[str, Any]] = []
    expected_sha = scope["expected_merge_commit_sha"]

    source = observation.get("source_workflow") or {}
    if not (
        source.get("event") == "push"
        and source.get("head_branch") == "main"
        and source.get("head_sha") == expected_sha
        and source.get("status") == "completed"
        and source.get("conclusion") == "success"
    ):
        failures.append({"reason": "SOURCE_WORKFLOW_MISMATCH"})

    pr = observation.get("pull_request") or {}
    if not (
        pr.get("merged") is True
        and pr.get("state") in {"MERGED", "closed"}
        and pr.get("merge_commit_sha") == expected_sha
        and isinstance(pr.get("number"), int)
        and pr["number"] > 0
    ):
        failures.append({"reason": "MERGED_PR_MISMATCH"})

    main = observation.get("branch_readback") or {}
    if main.get("branch") != "main" or main.get("head_sha") != expected_sha:
        failures.append({"reason": "MAIN_HEAD_MISMATCH"})

    declared = {item["path"]: item for item in scope["declared_paths"]}
    observed_rows = observation.get("files")
    if not isinstance(observed_rows, list):
        observed_rows = []
        failures.append({"reason": "FILE_OBSERVATIONS_REQUIRED"})
    observed: dict[str, dict[str, Any]] = {}
    for row in observed_rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str):
            failures.append({"reason": "FILE_OBSERVATION_INVALID"})
            continue
        path = row["path"]
        if path in observed:
            failures.append({"reason": "FILE_OBSERVATION_DUPLICATE", "path": path})
            continue
        observed[path] = row

    extra = sorted(set(observed) - set(declared))
    for path in extra:
        failures.append({"reason": "UNDECLARED_FILE_EVIDENCE", "path": path})

    for path, expected in declared.items():
        actual = observed.get(path)
        if actual is None:
            failures.append({"reason": "DECLARED_FILE_MISSING", "path": path})
            continue
        if actual.get("sha256") != expected["expected_sha256"]:
            failures.append({"reason": "FILE_SHA256_MISMATCH", "path": path})
        if actual.get("git_blob") != expected["expected_git_blob"]:
            failures.append({"reason": "FILE_GIT_BLOB_MISMATCH", "path": path})
        if actual.get("commit_sha") != expected_sha:
            failures.append({"reason": "FILE_SOURCE_REVISION_MISMATCH", "path": path})

    required_invariants = scope.get("repository_invariants") or []
    observed_invariants = observation.get("repository_invariants") or {}
    if not isinstance(required_invariants, list) or not isinstance(observed_invariants, dict):
        failures.append({"reason": "REPOSITORY_INVARIANT_SHAPE_INVALID"})
    else:
        for invariant in required_invariants:
            if not isinstance(invariant, str) or not invariant:
                failures.append({"reason": "REPOSITORY_INVARIANT_INVALID"})
            elif observed_invariants.get(invariant) is not True:
                failures.append({"reason": "REPOSITORY_INVARIANT_FAILED", "invariant": invariant})

    if failures:
        return _receipt("RECONCILIATION_FAILED", False, "POST_MERGE_READBACK_MISMATCH", request=request, scope=scope, failures=failures, observed_paths=list(observed))
    return _receipt("RECONCILED", True, "DECLARED_POST_MERGE_SCOPE_VERIFIED", request=request, scope=scope, failures=[], observed_paths=list(observed))
