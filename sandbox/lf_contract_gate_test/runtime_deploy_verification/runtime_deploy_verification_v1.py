#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SAFE_REL_PATH = re.compile(r"^(?!/)(?!.*(?:^|/)\.\.(?:/|$))[A-Za-z0-9._/@+-]+(?:/[A-Za-z0-9._/@+-]+)*$")
CAPABILITY_CODE = "RUNTIME_DEPLOY_VERIFICATION"
ENTRY_ACCEPTED = "ORCHESTRATOR_ENTRY_ACCEPTED"
FORBIDDEN_OBSERVATION_KEYS = {
    "deploy",
    "restart",
    "symlink_switch",
    "asset_update",
    "asset_reconcile",
    "next_gate",
    "promotion",
    "rebind",
}


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()


def scope_digest(scope: dict[str, Any]) -> str:
    return canonical_sha256({k: v for k, v in scope.items() if k != "scope_digest"})


def receipt_digest(receipt: dict[str, Any]) -> str:
    return canonical_sha256({k: v for k, v in receipt.items() if k != "receipt_digest"})


def observation_digest(observation: dict[str, Any]) -> str:
    return canonical_sha256({k: v for k, v in observation.items() if k != "receipt_digest"})


def _result(
    *,
    request: dict[str, Any],
    scope: dict[str, Any],
    ready: bool,
    decision: str,
    reason: str,
    failures: list[dict[str, Any]],
) -> dict[str, Any]:
    out = {
        "schema_version": "LF_RUNTIME_DEPLOY_VERIFICATION_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "ready": ready,
        "decision": decision,
        "reason": reason,
        "plan_digest": request.get("plan_digest"),
        "scope_digest": scope.get("scope_digest"),
        "target": scope.get("target"),
        "source_revision": request.get("source_revision"),
        "failures": failures,
        "deploy_performed": False,
        "restart_performed": False,
        "symlink_switch_performed": False,
        "asset_mutation_performed": False,
        "promotion_performed": False,
        "next_gate_selected": False,
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out


def _validate_request(request: dict[str, Any]) -> str | None:
    if request.get("capability_code") != CAPABILITY_CODE:
        return "CAPABILITY_CODE_MISMATCH"
    entry = request.get("entry_guard_readback")
    if not isinstance(entry, dict) or entry.get("decision") != ENTRY_ACCEPTED:
        return "ORCHESTRATOR_ENTRY_REQUIRED"
    for field in (
        "orchestrator_execution_id",
        "consumer_execution_id",
        "plan_digest",
        "dispatch_receipt_id",
        "request_digest",
        "source_revision",
    ):
        if not isinstance(request.get(field), str) or not request[field]:
            return f"REQUEST_FIELD_MISSING:{field}"
    if not HEX40.fullmatch(request["source_revision"]):
        return "SOURCE_REVISION_INVALID"
    return None


def _normalize_manifest(rows: Any) -> tuple[dict[str, str], str | None]:
    if not isinstance(rows, list) or not rows:
        return {}, "MANIFEST_REQUIRED"
    out: dict[str, str] = {}
    for row in rows:
        if not isinstance(row, dict):
            return {}, "MANIFEST_ROW_INVALID"
        path = row.get("path")
        sha = row.get("sha256")
        if not isinstance(path, str) or not SAFE_REL_PATH.fullmatch(path):
            return {}, "MANIFEST_PATH_INVALID"
        if path in out:
            return {}, "MANIFEST_PATH_DUPLICATE"
        if not isinstance(sha, str) or not HEX64.fullmatch(sha):
            return {}, "MANIFEST_SHA256_INVALID"
        out[path] = sha
    return out, None


def _validate_scope(scope: dict[str, Any], request: dict[str, Any]) -> tuple[dict[str, str], str | None]:
    if scope.get("schema_version") != "LF_RUNTIME_DEPLOY_VERIFICATION_SCOPE_V1":
        return {}, "SCOPE_SCHEMA_MISMATCH"
    if scope.get("plan_digest") != request.get("plan_digest"):
        return {}, "REQUEST_PLAN_DIGEST_MISMATCH"
    if scope.get("source_revision") != request.get("source_revision"):
        return {}, "REQUEST_SOURCE_REVISION_MISMATCH"
    if scope.get("scope_digest") != scope_digest(scope):
        return {}, "SCOPE_DIGEST_MISMATCH"
    target = scope.get("target")
    if not isinstance(target, dict) or not isinstance(target.get("target_code"), str) or not target["target_code"]:
        return {}, "TARGET_REQUIRED"
    deployment = scope.get("deployment")
    if not isinstance(deployment, dict):
        return {}, "DEPLOYMENT_SCOPE_REQUIRED"
    for field in ("effect_operation_code", "deployment_execution_id", "expected_release_ref"):
        if not isinstance(deployment.get(field), str) or not deployment[field]:
            return {}, f"DEPLOYMENT_FIELD_MISSING:{field}"
    expected_source_sha = deployment.get("expected_source_sha")
    if expected_source_sha != request.get("source_revision") or not HEX40.fullmatch(expected_source_sha or ""):
        return {}, "DEPLOYMENT_SOURCE_REVISION_MISMATCH"
    expected_state = scope.get("expected_preserved_state")
    if not isinstance(expected_state, dict) or not expected_state:
        return {}, "EXPECTED_PRESERVED_STATE_REQUIRED"
    return _normalize_manifest(deployment.get("required_files"))


def _validate_effect_receipt(receipt: Any, scope: dict[str, Any]) -> str | None:
    if not isinstance(receipt, dict):
        return "DEPLOYMENT_RECEIPT_REQUIRED"
    if receipt.get("schema_version") != "LF_RUNTIME_DEPLOY_EFFECT_RECEIPT_V1":
        return "DEPLOYMENT_RECEIPT_SCHEMA_MISMATCH"
    deployment = scope["deployment"]
    target = scope["target"]
    expected = {
        "effect_operation_code": deployment["effect_operation_code"],
        "deployment_execution_id": deployment["deployment_execution_id"],
        "target_code": target["target_code"],
        "source_sha": deployment["expected_source_sha"],
        "release_ref": deployment["expected_release_ref"],
    }
    for field, value in expected.items():
        if receipt.get(field) != value:
            return f"DEPLOYMENT_RECEIPT_{field.upper()}_MISMATCH"
    if receipt.get("effect_applied") is not True:
        return "DEPLOYMENT_EFFECT_NOT_APPLIED"
    if receipt.get("install_exit_zero") is not True:
        return "DEPLOYMENT_INSTALL_NOT_CLEAN"
    digest = receipt.get("receipt_digest")
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        return "DEPLOYMENT_RECEIPT_DIGEST_INVALID"
    if digest != receipt_digest(receipt):
        return "DEPLOYMENT_RECEIPT_DIGEST_MISMATCH"
    return None


def _validate_read_only_observation(row: Any, schema_version: str) -> str | None:
    if not isinstance(row, dict):
        return "OBSERVATION_REQUIRED"
    if row.get("schema_version") != schema_version:
        return "OBSERVATION_SCHEMA_MISMATCH"
    if row.get("read_only") is not True:
        return "READ_ONLY_REQUIRED"
    if row.get("mutation_performed") is not False:
        return "MUTATION_FORBIDDEN"
    if any(key in row for key in FORBIDDEN_OBSERVATION_KEYS):
        return "MUTATION_ROUTING_FIELD_FORBIDDEN"
    digest = row.get("receipt_digest")
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        return "OBSERVATION_DIGEST_INVALID"
    if digest != observation_digest(row):
        return "OBSERVATION_DIGEST_MISMATCH"
    return None


def evaluate_runtime_deploy_verification(
    *,
    request: dict[str, Any],
    scope: dict[str, Any],
    deployment_receipt: dict[str, Any],
    manifest_observation: dict[str, Any],
    health_observation: dict[str, Any],
    state_observation: dict[str, Any],
) -> dict[str, Any]:
    err = _validate_request(request)
    if err:
        return _result(request=request, scope=scope, ready=False, decision="VERIFICATION_FAILED", reason=err, failures=[{"reason": err}])
    expected_manifest, err = _validate_scope(scope, request)
    if err:
        return _result(request=request, scope=scope, ready=False, decision="VERIFICATION_FAILED", reason=err, failures=[{"reason": err}])

    failures: list[dict[str, Any]] = []
    err = _validate_effect_receipt(deployment_receipt, scope)
    if err:
        failures.append({"component": "deployment_receipt", "reason": err})

    err = _validate_read_only_observation(manifest_observation, "LF_RUNTIME_DEPLOY_MANIFEST_OBSERVATION_V1")
    if err:
        failures.append({"component": "manifest", "reason": err})
    else:
        observed_manifest, manifest_err = _normalize_manifest(manifest_observation.get("files"))
        if manifest_err:
            failures.append({"component": "manifest", "reason": manifest_err})
        elif observed_manifest != expected_manifest:
            missing = sorted(set(expected_manifest) - set(observed_manifest))
            extra = sorted(set(observed_manifest) - set(expected_manifest))
            mismatched = sorted(
                p for p in set(expected_manifest).intersection(observed_manifest)
                if expected_manifest[p] != observed_manifest[p]
            )
            failures.append({
                "component": "manifest",
                "reason": "DEPLOYED_MANIFEST_MISMATCH",
                "missing_paths": missing,
                "extra_paths": extra,
                "hash_mismatch_paths": mismatched,
            })

    err = _validate_read_only_observation(health_observation, "LF_RUNTIME_DEPLOY_HEALTH_OBSERVATION_V1")
    if err:
        failures.append({"component": "health", "reason": err})
    else:
        if health_observation.get("service_active") is not True:
            failures.append({"component": "health", "reason": "SERVICE_NOT_ACTIVE"})
        if health_observation.get("health_ok") is not True:
            failures.append({"component": "health", "reason": "HEALTH_NOT_OK"})
        if health_observation.get("runtime_endpoint_source_sha") != request["source_revision"]:
            failures.append({"component": "health", "reason": "RUNTIME_SOURCE_SHA_MISMATCH"})

    err = _validate_read_only_observation(state_observation, "LF_RUNTIME_DEPLOY_STATE_OBSERVATION_V1")
    if err:
        failures.append({"component": "state", "reason": err})
    else:
        if state_observation.get("current_state") != scope.get("expected_preserved_state"):
            failures.append({"component": "state", "reason": "PRESERVED_STATE_MISMATCH"})
        if state_observation.get("automatic_promotion_observed") is not False:
            failures.append({"component": "state", "reason": "AUTOMATIC_PROMOTION_FORBIDDEN"})

    if failures:
        return _result(
            request=request,
            scope=scope,
            ready=False,
            decision="VERIFICATION_FAILED",
            reason="RUNTIME_DEPLOY_READBACK_MISMATCH",
            failures=failures,
        )
    return _result(
        request=request,
        scope=scope,
        ready=True,
        decision="VERIFICATION_VERIFIED",
        reason="EXACT_DEPLOYMENT_RECEIPT_AND_READBACK_VERIFIED",
        failures=[],
    )
