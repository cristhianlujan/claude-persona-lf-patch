from __future__ import annotations

import copy
import hashlib
import json
import re
from typing import Any, Dict, Iterable, List

HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
TARGET_SET_EVENT_ID = 19549
CAPABILITY_ORDER = (
    "GITHUB_RECONCILIATION",
    "AUTHORITY_READBACK",
    "RUNTIME_DEPLOY_VERIFICATION",
    "FINAL_EVIDENCE",
    "CLOSURE_GATE",
)
READY_CURRENTNESS = {"CURRENT", "CURRENT_REBOUND"}
SELF_DIGEST = "$SELF"


class PostPaseRouterBlocked(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise PostPaseRouterBlocked(code)


def controls_digest(controls: Iterable[Dict[str, Any]]) -> str:
    rows = sorted(
        ({"control_code": c["capability_code"], "disposition": c["disposition"]} for c in controls),
        key=lambda x: x["control_code"],
    )
    return _sha256(rows)


def _validate_entry(request: Dict[str, Any]) -> None:
    entry = request.get("orchestrator_entry") or {}
    _require(entry.get("decision") == "ORCHESTRATOR_ENTRY_ACCEPTED", "ORCHESTRATOR_ENTRY_REQUIRED")
    _require(entry.get("orchestrator_execution_id") == request["pase_orchestrator_execution_id"], "ENTRY_EXECUTION_CROSSBIND")
    _require(entry.get("capability_code") == "POST_PASE_ROUTER", "ENTRY_CAPABILITY_CROSSBIND")


def _validate_identity(request: Dict[str, Any]) -> None:
    for field in (
        "post_pase_execution_id",
        "pase_orchestrator_execution_id",
        "source_pase_execution_id",
        "repository",
        "target_branch",
        "merge_sha",
    ):
        _require(isinstance(request.get(field), str) and bool(request[field]), f"MISSING_{field.upper()}")
    _require(bool(HEX40.fullmatch(request["merge_sha"])), "INVALID_MERGE_SHA")
    _require(request.get("target_set_event_id") == TARGET_SET_EVENT_ID, "TARGET_SET_EVENT_MISMATCH")


def _forbid_contamination(request: Dict[str, Any]) -> None:
    forbidden = {
        "owner",
        "runner",
        "carrier",
        "owner_map",
        "control_execution_request",
        "control_results",
        "receipts",
        "raw_evidence",
        "evidence_ledger",
        "next_gate",
    }
    _require(not (forbidden & set(request)), "ROUTER_RESPONSIBILITY_CONTAMINATION")


def _validate_currentness(request: Dict[str, Any]) -> str:
    receipt = request.get("currentness_receipt") or {}
    _require(receipt.get("schema_version") == "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1", "CURRENTNESS_SCHEMA")
    _require(receipt.get("authority_layer") == "CURRENTNESS_AUTHORITY", "CURRENTNESS_AUTHORITY_LAYER")
    _require(receipt.get("decision") in READY_CURRENTNESS and receipt.get("ready") is True, "CURRENTNESS_NOT_READY")
    _require(receipt.get("current_revision") == request["merge_sha"], "CURRENTNESS_REVISION_MISMATCH")
    digest = receipt.get("receipt_sha256")
    _require(isinstance(digest, str) and bool(HEX64.fullmatch(digest)), "CURRENTNESS_RECEIPT_DIGEST_INVALID")
    return digest


def _safe_path(path: Any) -> bool:
    return (
        isinstance(path, str)
        and bool(path)
        and not path.startswith("/")
        and "\\" not in path
        and ".." not in path.split("/")
        and not any(ch in path for ch in "*?[]")
    )


def _declared_paths(request: Dict[str, Any]) -> List[Dict[str, str]]:
    rows = request.get("declared_paths")
    _require(isinstance(rows, list) and rows, "DECLARED_PATHS_REQUIRED")
    out: List[Dict[str, str]] = []
    seen = set()
    for row in rows:
        _require(isinstance(row, dict), "DECLARED_PATH_SHAPE")
        path = row.get("path")
        kind = row.get("kind")
        _require(_safe_path(path), "DECLARED_PATH_INVALID")
        _require(kind in {"CHANGED", "ANCHOR"}, "DECLARED_PATH_KIND_INVALID")
        _require(path not in seen, "DECLARED_PATH_DUPLICATE")
        seen.add(path)
        out.append({"path": path, "kind": kind})
    return sorted(out, key=lambda x: (x["path"], x["kind"]))


def _repository_invariants(request: Dict[str, Any]) -> List[str]:
    rows = request.get("repository_invariants") or []
    _require(isinstance(rows, list), "REPOSITORY_INVARIANTS_SHAPE")
    _require(all(isinstance(x, str) and x for x in rows), "REPOSITORY_INVARIANT_INVALID")
    _require(len(rows) == len(set(rows)), "REPOSITORY_INVARIANT_DUPLICATE")
    return sorted(rows)


def _authority_scopes(request: Dict[str, Any]) -> List[Dict[str, Any]]:
    rows = request.get("authority_scopes") or []
    _require(isinstance(rows, list), "AUTHORITY_SCOPES_SHAPE")
    out: List[Dict[str, Any]] = []
    seen = set()
    required = {"check_id", "adapter_code", "subject_ref", "authority_ref", "expected_source_revision", "currentness_required"}
    for row in rows:
        _require(isinstance(row, dict) and required.issubset(row), "AUTHORITY_SCOPE_FIELDS")
        check_id = row.get("check_id")
        _require(isinstance(check_id, str) and check_id and check_id not in seen, "AUTHORITY_SCOPE_ID_INVALID_OR_DUPLICATE")
        seen.add(check_id)
        for field in ("adapter_code", "subject_ref", "authority_ref", "expected_source_revision"):
            _require(isinstance(row.get(field), str) and bool(row[field]), f"AUTHORITY_SCOPE_{field.upper()}_INVALID")
        _require(isinstance(row.get("currentness_required"), bool), "AUTHORITY_SCOPE_CURRENTNESS_FLAG_INVALID")
        out.append({k: row[k] for k in sorted(required)})
    return sorted(out, key=lambda x: x["check_id"])


def _runtime_scope(request: Dict[str, Any]) -> Dict[str, Any] | None:
    scope = request.get("runtime_deploy_scope")
    if scope is None:
        return None
    _require(isinstance(scope, dict), "RUNTIME_SCOPE_SHAPE")
    required = {"effect_operation_code", "deployment_execution_id", "target_code", "source_sha", "release_ref", "required_files"}
    _require(required.issubset(scope), "RUNTIME_SCOPE_FIELDS")
    for field in ("effect_operation_code", "deployment_execution_id", "target_code", "release_ref"):
        _require(isinstance(scope.get(field), str) and bool(scope[field]), f"RUNTIME_SCOPE_{field.upper()}_INVALID")
    _require(scope.get("source_sha") == request["merge_sha"], "RUNTIME_SCOPE_SOURCE_SHA_MISMATCH")
    files = scope.get("required_files")
    _require(isinstance(files, list) and files, "RUNTIME_REQUIRED_FILES_REQUIRED")
    normalized_files = []
    seen = set()
    for row in files:
        _require(isinstance(row, dict), "RUNTIME_REQUIRED_FILE_SHAPE")
        path = row.get("path")
        digest = row.get("sha256")
        _require(_safe_path(path), "RUNTIME_REQUIRED_FILE_PATH_INVALID")
        _require(path not in seen, "RUNTIME_REQUIRED_FILE_DUPLICATE")
        _require(isinstance(digest, str) and bool(HEX64.fullmatch(digest)), "RUNTIME_REQUIRED_FILE_DIGEST_INVALID")
        seen.add(path)
        normalized_files.append({"path": path, "sha256": digest})
    return {
        "effect_operation_code": scope["effect_operation_code"],
        "deployment_execution_id": scope["deployment_execution_id"],
        "target_code": scope["target_code"],
        "source_sha": scope["source_sha"],
        "release_ref": scope["release_ref"],
        "required_files": sorted(normalized_files, key=lambda x: x["path"]),
    }


def _scope_digest(scope: Dict[str, Any]) -> str:
    normalized = copy.deepcopy(scope)
    if "plan_digest" in normalized:
        normalized["plan_digest"] = SELF_DIGEST
    return _sha256(normalized)


def _control(capability_code: str, disposition: str, scope: Dict[str, Any] | None) -> Dict[str, Any]:
    row: Dict[str, Any] = {"capability_code": capability_code, "disposition": disposition, "scope": scope}
    row["scope_digest"] = _scope_digest(scope) if scope is not None else None
    return row


def _plan_preimage(plan: Dict[str, Any]) -> Dict[str, Any]:
    preimage = copy.deepcopy(plan)
    preimage["plan_digest"] = SELF_DIGEST
    for control in preimage.get("controls") or []:
        scope = control.get("scope")
        if isinstance(scope, dict) and "plan_digest" in scope:
            scope["plan_digest"] = SELF_DIGEST
    return preimage


def build_post_pase_plan(request: Dict[str, Any]) -> Dict[str, Any]:
    _validate_identity(request)
    _validate_entry(request)
    _forbid_contamination(request)
    currentness_sha = _validate_currentness(request)
    paths = _declared_paths(request)
    invariants = _repository_invariants(request)
    authority_scopes = _authority_scopes(request)
    runtime_scope = _runtime_scope(request)

    controls = [
        _control(
            "GITHUB_RECONCILIATION",
            "REQUIRED",
            {
                "schema_version": "LF_GITHUB_RECONCILIATION_SCOPE_V1",
                "repository": request["repository"],
                "target_branch": request["target_branch"],
                "plan_digest": SELF_DIGEST,
                "expected_merge_commit_sha": request["merge_sha"],
                "declared_paths": paths,
                "repository_invariants": invariants,
            },
        ),
        _control(
            "AUTHORITY_READBACK",
            "REQUIRED" if authority_scopes else "NOT_APPLICABLE",
            {
                "schema_version": "LF_AUTHORITY_READBACK_SCOPE_V1",
                "plan_digest": SELF_DIGEST,
                "checks": authority_scopes,
            }
            if authority_scopes
            else None,
        ),
        _control(
            "RUNTIME_DEPLOY_VERIFICATION",
            "REQUIRED" if runtime_scope else "NOT_APPLICABLE",
            ({"schema_version": "LF_RUNTIME_DEPLOY_VERIFICATION_SCOPE_V1", "plan_digest": SELF_DIGEST, **runtime_scope})
            if runtime_scope
            else None,
        ),
        _control(
            "FINAL_EVIDENCE",
            "REQUIRED",
            {
                "schema_version": "LF_FINAL_EVIDENCE_PLAN_SCOPE_V1",
                "plan_digest": SELF_DIGEST,
                "merge_sha": request["merge_sha"],
            },
        ),
        _control(
            "CLOSURE_GATE",
            "REQUIRED",
            {
                "schema_version": "LF_CLOSURE_GATE_PLAN_SCOPE_V1",
                "plan_digest": SELF_DIGEST,
                "merge_sha": request["merge_sha"],
            },
        ),
    ]
    _require(tuple(c["capability_code"] for c in controls) == CAPABILITY_ORDER, "TARGET_CAPABILITY_SET_DRIFT")
    c_digest = controls_digest(controls)
    plan: Dict[str, Any] = {
        "schema_version": "LF_POST_PASE_PLAN_V1",
        "router_code": "POST_PASE_ROUTER_V1",
        "target_set_event_id": TARGET_SET_EVENT_ID,
        "post_pase_execution_id": request["post_pase_execution_id"],
        "pase_orchestrator_execution_id": request["pase_orchestrator_execution_id"],
        "source_pase_execution_id": request["source_pase_execution_id"],
        "repository": request["repository"],
        "target_branch": request["target_branch"],
        "merge_sha": request["merge_sha"],
        "currentness_receipt_sha256": currentness_sha,
        "controls_digest": c_digest,
        "controls": controls,
        "control_execution_performed": False,
        "control_logic_embedded": False,
        "owner_recalculation_performed": False,
        "evidence_collection_performed": False,
        "immutable": True,
        "plan_digest": SELF_DIGEST,
    }
    digest = _sha256(_plan_preimage(plan))
    plan["plan_digest"] = digest
    for control in plan["controls"]:
        if isinstance(control.get("scope"), dict) and "plan_digest" in control["scope"]:
            control["scope"]["plan_digest"] = digest
    return plan


def verify_post_pase_plan(plan: Dict[str, Any]) -> bool:
    _require(isinstance(plan, dict), "PLAN_SHAPE")
    _require(plan.get("schema_version") == "LF_POST_PASE_PLAN_V1", "PLAN_SCHEMA")
    _require(plan.get("router_code") == "POST_PASE_ROUTER_V1", "PLAN_ROUTER_CODE")
    _require(plan.get("target_set_event_id") == TARGET_SET_EVENT_ID, "PLAN_TARGET_SET_EVENT")
    _require(plan.get("immutable") is True, "PLAN_IMMUTABILITY_FLAG")
    _require(plan.get("control_execution_performed") is False, "PLAN_CONTROL_EXECUTION_FORBIDDEN")
    _require(plan.get("control_logic_embedded") is False, "PLAN_CONTROL_LOGIC_FORBIDDEN")
    _require(plan.get("owner_recalculation_performed") is False, "PLAN_OWNER_RECALCULATION_FORBIDDEN")
    _require(plan.get("evidence_collection_performed") is False, "PLAN_EVIDENCE_COLLECTION_FORBIDDEN")
    controls = plan.get("controls")
    _require(isinstance(controls, list) and tuple(c.get("capability_code") for c in controls) == CAPABILITY_ORDER, "PLAN_TARGET_SET_DRIFT")
    _require(plan.get("controls_digest") == controls_digest(controls), "PLAN_CONTROLS_DIGEST_MISMATCH")
    digest = plan.get("plan_digest")
    _require(isinstance(digest, str) and bool(HEX64.fullmatch(digest)), "PLAN_DIGEST_INVALID")
    for control in controls:
        scope = control.get("scope")
        disposition = control.get("disposition")
        _require(disposition in {"REQUIRED", "NOT_APPLICABLE"}, "PLAN_DISPOSITION_INVALID")
        if disposition == "NOT_APPLICABLE":
            _require(scope is None and control.get("scope_digest") is None, "PLAN_NA_SCOPE_MUST_BE_NULL")
        else:
            _require(isinstance(scope, dict), "PLAN_REQUIRED_SCOPE_MISSING")
            _require(scope.get("plan_digest") == digest, "PLAN_SCOPE_DIGEST_CROSSBIND")
            _require(control.get("scope_digest") == _scope_digest(scope), "PLAN_SCOPE_DIGEST_MISMATCH")
    _require(_sha256(_plan_preimage(plan)) == digest, "PLAN_DIGEST_MISMATCH")
    return True
