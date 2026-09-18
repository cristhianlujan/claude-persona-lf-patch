#!/usr/bin/env python3
"""Canonical CI execution plan for CI_FAST_DEEP_LANE_ROUTER.

This is not a second router. It consumes the existing lane decision and the
declarative impact registry to turn required_controls into the single
applicability plan consumed by all CI carriers.
"""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping

SCHEMA_VERSION = "lf-ci-execution-plan/v2"
REGISTRY_VERSION = "lf-ci-control-impact-registry/v2"
REGISTRY_PATH = Path(__file__).with_name("lf_ci_control_impact_registry_v2.json")
SELF_PREFIX = "sandbox/lf_contract_gate_test/s28_ci_lane_router/"
CARRIER_SELF_PATHS = frozenset({
    ".github/workflows/lf-contract-check.yml",
    ".github/workflows/validate-lf-packs.yml",
    ".github/workflows/lf-bootstrap-reproducibility.yml",
})


class PlanError(ValueError):
    pass


@dataclass(frozen=True)
class ImpactControl:
    control_id: str
    carrier: str
    path_matchers: tuple[Mapping[str, str], ...]
    material_matchers: tuple[Mapping[str, str], ...]
    dependencies: tuple[str, ...]


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _safe_path(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value:
        return False
    parts = PurePosixPath(value).parts
    return bool(parts) and all(p not in {".", ".."} for p in parts)


def load_registry(path: Path = REGISTRY_PATH) -> tuple[tuple[str, ...], tuple[str, ...], tuple[ImpactControl, ...]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schema_version") != REGISTRY_VERSION:
        raise PlanError("FAIL_CI_IMPACT_REGISTRY_SCHEMA")
    full = data.get("full_regression_controls")
    rows = data.get("controls")
    if not isinstance(full, list) or not full or len(full) != len(set(full)):
        raise PlanError("FAIL_CI_IMPACT_REGISTRY_FULL_UNIVERSE")
    if not isinstance(rows, list) or not rows:
        raise PlanError("FAIL_CI_IMPACT_REGISTRY_CONTROLS")
    controls: list[ImpactControl] = []
    seen: set[str] = set()
    for raw in rows:
        if not isinstance(raw, dict):
            raise PlanError("FAIL_CI_IMPACT_REGISTRY_ENTRY")
        expected = {"control_id","carrier","path_matchers","material_matchers","dependencies"}
        if set(raw) != expected:
            raise PlanError(f"FAIL_CI_IMPACT_REGISTRY_FIELDS:{sorted(set(raw)^expected)}")
        cid = raw["control_id"]
        carrier = raw["carrier"]
        if not isinstance(cid, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", cid):
            raise PlanError(f"FAIL_CI_IMPACT_CONTROL_ID:{cid!r}")
        if cid in seen:
            raise PlanError(f"FAIL_CI_IMPACT_CONTROL_DUPLICATE:{cid}")
        seen.add(cid)
        if not isinstance(carrier, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", carrier):
            raise PlanError(f"FAIL_CI_IMPACT_CARRIER:{cid}")
        pm = raw["path_matchers"]
        mm = raw["material_matchers"]
        deps = raw["dependencies"]
        if not isinstance(pm, list) or not isinstance(mm, list) or not isinstance(deps, list):
            raise PlanError(f"FAIL_CI_IMPACT_MATCHER_SHAPE:{cid}")
        for matcher in [*pm, *mm]:
            if not isinstance(matcher, dict) or set(matcher) != {"kind","value"}:
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_FIELDS:{cid}")
            if not isinstance(matcher["kind"], str) or not isinstance(matcher["value"], str):
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_TYPES:{cid}")
            if matcher["kind"] in {"prefix","exact"} and not _safe_path(matcher["value"]):
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_PATH:{cid}")
            if matcher["kind"] not in {"prefix","exact","sql_regex","path_or_sql_regex"}:
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_KIND:{cid}:{matcher['kind']}")
            if matcher["kind"] in {"sql_regex","path_or_sql_regex"}:
                try:
                    re.compile(matcher["value"])
                except re.error as exc:
                    raise PlanError(f"FAIL_CI_IMPACT_MATCHER_REGEX:{cid}:{exc}") from exc
        if any(not isinstance(x,str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*",x) for x in deps):
            raise PlanError(f"FAIL_CI_IMPACT_DEPENDENCY_ID:{cid}")
        controls.append(ImpactControl(cid,carrier,tuple(pm),tuple(mm),tuple(deps)))
    unknown_full = sorted(set(full)-seen)
    if unknown_full:
        raise PlanError(f"FAIL_CI_IMPACT_FULL_REGRESSION_UNKNOWN_CONTROL:{unknown_full}")
    for control in controls:
        unknown = sorted(set(control.dependencies)-seen)
        if unknown:
            raise PlanError(f"FAIL_CI_IMPACT_UNKNOWN_DEPENDENCY:{control.control_id}:{unknown}")
    return tuple(sorted(seen)), tuple(sorted(full)), tuple(controls)


def _path_matches(path: str, matcher: Mapping[str,str]) -> bool:
    kind = matcher["kind"]
    value = matcher["value"]
    if kind == "prefix":
        return path.startswith(value)
    if kind == "exact":
        return path == value
    return False


def _material_matches(path: str, content: str | None, matcher: Mapping[str,str]) -> bool:
    kind = matcher["kind"]
    value = matcher["value"]
    if kind == "sql_regex":
        return content is not None and re.search(value, content) is not None
    if kind == "path_or_sql_regex":
        return re.search(value, path) is not None or (content is not None and re.search(value, content) is not None)
    return False


def _read_material(repo_root: Path, path: str) -> tuple[str | None, dict[str,Any]]:
    target = repo_root / path
    if not target.is_file():
        return None, {"path":path,"state":"MISSING_OR_DELETED"}
    raw = target.read_bytes()
    evidence: dict[str,Any] = {
        "path": path,
        "state": "PRESENT",
        "sha256": _sha(raw),
        "bytes": len(raw),
    }
    if path.startswith("supabase/migrations/") and path.endswith(".sql"):
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise PlanError(f"FAIL_CI_MIGRATION_NON_UTF8:{path}") from exc
        evidence["kind"] = "SQL_MIGRATION"
        return content, evidence
    evidence["kind"] = "FILE"
    return None, evidence


def build_plan(
    *,
    changed_paths: Iterable[str],
    lane_required_controls: Iterable[str],
    lane_mode: str,
    repo_root: Path,
    force_full: bool = False,
    force_full_reason: str | None = None,
) -> dict[str,Any]:
    control_universe, full_regression_controls, controls = load_registry()
    by_id = {c.control_id:c for c in controls}
    changed = tuple(sorted({p.strip() for p in changed_paths if isinstance(p,str) and p.strip()}))
    if not changed and not force_full:
        force_full = True
        force_full_reason = force_full_reason or "NO_CHANGED_PATHS_FAIL_CLOSED"

    unknown_lane_control = sorted(set(lane_required_controls)-set(control_universe))
    if unknown_lane_control:
        raise PlanError(f"FAIL_CI_PLAN_UNKNOWN_LANE_CONTROL:{unknown_lane_control}")

    self_change = any(p.startswith(SELF_PREFIX) or p in CARRIER_SELF_PATHS for p in changed)
    unknown_lane = lane_mode.startswith("DEEP_SHARED_UNKNOWN")
    full_regression = bool(force_full or self_change or unknown_lane)
    full_reason = (
        force_full_reason
        if force_full
        else "CI_APPLICABILITY_AUTHORITY_SELF_CHANGE"
        if self_change
        else "UNKNOWN_SCOPE_FAIL_CLOSED"
        if unknown_lane
        else None
    )

    required: set[str] = set(lane_required_controls)
    reason_map: dict[str,set[str]] = {cid:set() for cid in control_universe}
    material_evidence: list[dict[str,Any]] = []
    handled_paths: set[str] = set()

    if full_regression:
        required.update(full_regression_controls)
        for cid in full_regression_controls:
            reason_map[cid].add(f"FULL_REGRESSION:{full_reason}")
        for path in changed:
            _, evidence = _read_material(repo_root,path)
            material_evidence.append(evidence)
            handled_paths.add(path)
    else:
        for path in changed:
            content, evidence = _read_material(repo_root,path)
            matched_controls: set[str] = set()
            for control in controls:
                if any(_path_matches(path,m) for m in control.path_matchers):
                    matched_controls.add(control.control_id)
                    reason_map[control.control_id].add(f"PATH:{path}")
                if any(_material_matches(path,content,m) for m in control.material_matchers):
                    matched_controls.add(control.control_id)
                    reason_map[control.control_id].add(f"MATERIAL:{path}")
            if matched_controls:
                handled_paths.add(path)
                required.update(matched_controls)
            evidence["matched_controls"] = sorted(matched_controls)
            material_evidence.append(evidence)

        unhandled = sorted(set(changed)-handled_paths)
        if unhandled:
            full_regression = True
            full_reason = "UNMAPPED_CHANGED_PATH_FAIL_CLOSED"
            required.update(full_regression_controls)
            for cid in full_regression_controls:
                reason_map[cid].add(f"FULL_REGRESSION:{full_reason}")
            material_evidence.append({"unmapped_paths":unhandled,"state":"FAIL_CLOSED_TO_FULL"})

    # Dependency closure is computed centrally and recursively.
    pending = list(required)
    while pending:
        cid = pending.pop()
        control = by_id.get(cid)
        if control is None:
            continue
        for dep in control.dependencies:
            if dep not in required:
                required.add(dep)
                pending.append(dep)
            reason_map[dep].add(f"DEPENDENCY_OF:{cid}")

    required_sorted = sorted(required)
    not_applicable = [
        {
            "control_id": cid,
            "carrier": by_id[cid].carrier,
            "reason": "NO_TRIGGER_AND_NOT_IN_DEPENDENCY_CLOSURE",
        }
        for cid in control_universe
        if cid not in required
    ]
    carrier_controls: dict[str,list[str]] = {}
    for cid in required_sorted:
        carrier_controls.setdefault(by_id[cid].carrier,[]).append(cid)
    for values in carrier_controls.values():
        values.sort()

    plan: dict[str,Any] = {
        "schema_version": SCHEMA_VERSION,
        "router_capability": "CI_FAST_DEEP_LANE_ROUTER",
        "lane_mode": lane_mode,
        "full_regression": full_regression,
        "full_regression_reason": full_reason,
        "changed_paths": list(changed),
        "material_evidence": material_evidence,
        "required_controls": required_sorted,
        "required_control_reasons": {cid:sorted(reason_map[cid]) for cid in required_sorted},
        "not_applicable_controls": not_applicable,
        "carrier_controls": dict(sorted(carrier_controls.items())),
        "control_universe": list(control_universe),
        "full_regression_control_set": list(full_regression_controls),
        "coverage_complete": len(required_sorted)+len(not_applicable)==len(control_universe),
    }
    if not plan["coverage_complete"]:
        raise PlanError("FAIL_CI_PLAN_COVERAGE_INCOMPLETE")
    plan["plan_sha256"] = _sha(_canonical(plan).encode("utf-8"))
    return plan
