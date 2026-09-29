#!/usr/bin/env python3
"""Canonical PASE merge-route producer owned by Changeset Governance.

The producer never decides control applicability. It consumes the already-built
lf-ci-execution-plan/v2 plus the repair-enforcement projection and emits exactly
one lf-pase-merge-route/v1 packet for PASE_MERGE_GATE_V1.

Route selection is declarative: known control-system surfaces are mapped to a
candidate_id by the Changeset Governance route registry. A PR that touches more
than one control-system candidate fails closed instead of silently choosing one.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any, Mapping, Iterable

PLAN_SCHEMA = "lf-ci-execution-plan/v2"
ENFORCEMENT_SCHEMA = "lf-pase-control-enforcement/v1"
ROUTE_SCHEMA = "lf-pase-merge-route/v1"
REGISTRY_SCHEMA = "lf-pase-control-system-route-registry/v1"
AUTHORITY = "CHANGESET_GOVERNANCE_LF_V1"
REPAIR_POLICY_ID = "PASE_CONTROL_REPAIR_QUARANTINE_V1"
MODES = {"EXECUTION_PLAN", "CONTROL_SYSTEM_QUALIFICATION"}
CONTROL_ID = re.compile(r"^[A-Z][A-Z0-9_]*$")
CANDIDATE_ID = re.compile(r"^[A-Z][A-Z0-9_-]*$")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REGISTRY_PATH = Path(__file__).with_name("lf_pase_control_system_route_registry_v1.json")


class PaseMergeRouteError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _safe_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value:
        return False
    parts = PurePosixPath(value).parts
    return bool(parts) and all(part not in {".", ".."} for part in parts)


def _sorted_unique_controls(value: Any) -> bool:
    return (
        isinstance(value, list)
        and value == sorted(value)
        and len(value) == len(set(value))
        and all(isinstance(v, str) and CONTROL_ID.fullmatch(v) for v in value)
    )


def _validate_plan(plan: Any) -> tuple[list[str], str]:
    if not isinstance(plan, Mapping) or plan.get("schema_version") != PLAN_SCHEMA:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_PLAN_SCHEMA")
    if plan.get("coverage_complete") is not True:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_PLAN_COVERAGE")
    required = plan.get("required_controls")
    if not _sorted_unique_controls(required):
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_PLAN_REQUIRED")
    digest = plan.get("plan_sha256")
    if not isinstance(digest, str) or SHA256.fullmatch(digest) is None:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_PLAN_DIGEST")
    return list(required), digest


def _validate_enforcement(enforcement: Any, required: list[str], plan_digest: str) -> list[str]:
    if not isinstance(enforcement, Mapping) or enforcement.get("schema_version") != ENFORCEMENT_SCHEMA:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_SCHEMA")
    if enforcement.get("authority") != AUTHORITY or enforcement.get("policy_id") != REPAIR_POLICY_ID:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_AUTHORITY")
    if enforcement.get("source_plan_sha256") != plan_digest:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_PLAN_DRIFT")
    if enforcement.get("required_controls") != required:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_REQUIRED_DRIFT")
    blocking = enforcement.get("blocking_controls")
    observe_only = enforcement.get("observe_only_controls")
    if not _sorted_unique_controls(blocking) or not _sorted_unique_controls(observe_only):
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_CONTROLS")
    if set(blocking) & set(observe_only) or set(blocking) | set(observe_only) != set(required):
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_PARTITION")
    claimed = enforcement.get("result_sha256")
    observed = dict(enforcement)
    observed.pop("result_sha256", None)
    if not isinstance(claimed, str) or SHA256.fullmatch(claimed) is None or _sha256(observed) != claimed:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_ENFORCEMENT_DIGEST")
    return list(blocking)


def load_registry(path: Path = REGISTRY_PATH) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise PaseMergeRouteError(f"FAIL_PASE_ROUTE_REGISTRY_READ:{exc.__class__.__name__}") from exc
    validate_registry(data)
    return data


def validate_registry(data: Any) -> None:
    if not isinstance(data, Mapping) or data.get("schema_version") != REGISTRY_SCHEMA:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_SCHEMA")
    if data.get("authority") != AUTHORITY:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_AUTHORITY")
    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_ENTRIES")
    seen: set[tuple[str, str]] = set()
    for row in entries:
        if not isinstance(row, Mapping) or set(row) != {"kind", "value", "candidate_id"}:
            raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_ENTRY_SHAPE")
        kind = row.get("kind")
        value = row.get("value")
        candidate_id = row.get("candidate_id")
        if kind not in {"exact", "prefix"} or not _safe_path(value):
            raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_MATCHER")
        if not isinstance(candidate_id, str) or CANDIDATE_ID.fullmatch(candidate_id) is None:
            raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_CANDIDATE")
        key = (kind, value)
        if key in seen:
            raise PaseMergeRouteError("FAIL_PASE_ROUTE_REGISTRY_DUPLICATE")
        seen.add(key)


def _matches(path: str, row: Mapping[str, Any]) -> bool:
    return path == row["value"] if row["kind"] == "exact" else path.startswith(row["value"])


def _candidate_for_path(path: str, entries: list[Mapping[str, Any]]) -> str | None:
    matches = [row for row in entries if _matches(path, row)]
    if not matches:
        return None
    max_specificity = max(len(str(row["value"])) for row in matches)
    finalists = [row for row in matches if len(str(row["value"])) == max_specificity]
    candidate_ids = {str(row["candidate_id"]) for row in finalists}
    if len(candidate_ids) != 1:
        raise PaseMergeRouteError(f"FAIL_PASE_ROUTE_REGISTRY_AMBIGUOUS:{path}")
    return next(iter(candidate_ids))


def classify_route(changed_paths: Iterable[str], registry: Mapping[str, Any]) -> tuple[str, str | None]:
    validate_registry(registry)
    changed = sorted({p.strip() for p in changed_paths if isinstance(p, str) and p.strip()})
    if not changed:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_CHANGED_PATHS_EMPTY")
    if any(not _safe_path(path) for path in changed):
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_CHANGED_PATH_INVALID")
    entries = list(registry["entries"])
    candidate_ids = {
        candidate_id
        for path in changed
        for candidate_id in [_candidate_for_path(path, entries)]
        if candidate_id is not None
    }
    if len(candidate_ids) > 1:
        raise PaseMergeRouteError(
            "FAIL_PASE_ROUTE_MULTIPLE_CONTROL_SYSTEM_CANDIDATES:" + ",".join(sorted(candidate_ids))
        )
    if candidate_ids:
        return "CONTROL_SYSTEM_QUALIFICATION", next(iter(candidate_ids))
    return "EXECUTION_PLAN", None


def build_merge_route(
    *,
    plan: Mapping[str, Any],
    enforcement: Mapping[str, Any],
    head_sha: str,
    changed_paths: Iterable[str],
    registry: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    if not isinstance(head_sha, str) or SHA40.fullmatch(head_sha) is None:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_HEAD")
    required, plan_digest = _validate_plan(plan)
    blocking = _validate_enforcement(enforcement, required, plan_digest)
    route_registry = dict(registry) if registry is not None else load_registry()
    mode, candidate_id = classify_route(changed_paths, route_registry)
    route: dict[str, Any] = {
        "schema_version": ROUTE_SCHEMA,
        "authority": AUTHORITY,
        "head_sha": head_sha,
        "source_revision": _sha256(route_registry),
        "mode": mode,
        "required_control_ids": blocking,
        "candidate_id": candidate_id,
    }
    if mode not in MODES:
        raise PaseMergeRouteError("FAIL_PASE_ROUTE_MODE_INTERNAL")
    return route
