#!/usr/bin/env python3
"""Canonical CI applicability plan.

Applicability is resolved by Changeset Governance + declarative impact rules.
FULL_REGRESSION is a consumer/verifier of this plan; it never expands it.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping

SCHEMA_VERSION = "lf-ci-execution-plan/v2"
REGISTRY_VERSION = "lf-ci-control-impact-registry/v2"
REGISTRY_PATH = Path(__file__).with_name("lf_ci_control_impact_registry_v2.json")
SELF_PREFIX = "sandbox/lf_contract_gate_test/s28_ci_lane_router/"
CARRIER_SELF_PATHS = {
    ".github/workflows/lf-contract-check.yml": "LF_CONTRACT_CHECK",
    ".github/workflows/validate-lf-packs.yml": "VALIDATE_LF_PACKS",
    ".github/workflows/lf-bootstrap-reproducibility.yml": "LF_BOOTSTRAP_REPRODUCIBILITY",
}
CANONICAL_CARRIERS = frozenset(CARRIER_SELF_PATHS.values())
PLAN_HASH_FIELDS = (
    "schema_version",
    "router_capability",
    "lane_mode",
    "applicability_authority",
    "applicability_decision",
    "full_regression",
    "full_regression_reason",
    "full_regression_semantics",
    "carrier_regression",
    "carrier_regression_reason",
    "carrier_regression_carriers",
    "carrier_regression_semantics",
    "local_applicability_decisions",
    "parallel_applicability_engine",
    "run_everything",
    "execution_ownership",
    "legacy_full_regression_registry_semantics",
    "changed_paths",
    "material_evidence",
    "required_controls",
    "required_control_reasons",
    "not_applicable_controls",
    "carrier_controls",
    "control_universe",
    "coverage_complete",
)


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


def load_registry(path: Path = REGISTRY_PATH) -> tuple[tuple[str, ...], tuple[ImpactControl, ...]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schema_version") != REGISTRY_VERSION:
        raise PlanError("FAIL_CI_IMPACT_REGISTRY_SCHEMA")
    rows = data.get("controls")
    if not isinstance(rows, list) or not rows:
        raise PlanError("FAIL_CI_IMPACT_REGISTRY_CONTROLS")

    controls: list[ImpactControl] = []
    seen: set[str] = set()
    for raw in rows:
        if not isinstance(raw, dict):
            raise PlanError("FAIL_CI_IMPACT_REGISTRY_ENTRY")
        expected = {"control_id", "carrier", "path_matchers", "material_matchers", "dependencies"}
        if set(raw) != expected:
            raise PlanError(f"FAIL_CI_IMPACT_REGISTRY_FIELDS:{sorted(set(raw)^expected)}")
        cid = raw["control_id"]
        carrier = raw["carrier"]
        if not isinstance(cid, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", cid):
            raise PlanError(f"FAIL_CI_IMPACT_CONTROL_ID:{cid!r}")
        if cid in seen:
            raise PlanError(f"FAIL_CI_IMPACT_CONTROL_DUPLICATE:{cid}")
        seen.add(cid)
        if not isinstance(carrier, str) or carrier not in CANONICAL_CARRIERS:
            raise PlanError(f"FAIL_CI_IMPACT_CARRIER:{cid}")
        pm = raw["path_matchers"]
        mm = raw["material_matchers"]
        deps = raw["dependencies"]
        if not isinstance(pm, list) or not isinstance(mm, list) or not isinstance(deps, list):
            raise PlanError(f"FAIL_CI_IMPACT_MATCHER_SHAPE:{cid}")
        for matcher in [*pm, *mm]:
            if not isinstance(matcher, dict) or set(matcher) != {"kind", "value"}:
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_FIELDS:{cid}")
            if not isinstance(matcher["kind"], str) or not isinstance(matcher["value"], str):
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_TYPES:{cid}")
            if matcher["kind"] in {"prefix", "exact"} and not _safe_path(matcher["value"]):
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_PATH:{cid}")
            if matcher["kind"] not in {"prefix", "exact", "sql_regex", "path_or_sql_regex"}:
                raise PlanError(f"FAIL_CI_IMPACT_MATCHER_KIND:{cid}:{matcher['kind']}")
            if matcher["kind"] in {"sql_regex", "path_or_sql_regex"}:
                try:
                    re.compile(matcher["value"])
                except re.error as exc:
                    raise PlanError(f"FAIL_CI_IMPACT_MATCHER_REGEX:{cid}:{exc}") from exc
        if any(not isinstance(x, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", x) for x in deps):
            raise PlanError(f"FAIL_CI_IMPACT_DEPENDENCY_ID:{cid}")
        controls.append(ImpactControl(cid, carrier, tuple(pm), tuple(mm), tuple(deps)))

    legacy_full = data.get("full_regression_controls")
    if legacy_full is not None:
        if (
            not isinstance(legacy_full, list)
            or len(legacy_full) != len(set(legacy_full))
            or any(not isinstance(cid, str) for cid in legacy_full)
        ):
            raise PlanError("FAIL_CI_IMPACT_REGISTRY_LEGACY_FULL_FIELD")
        unknown_legacy = sorted(set(legacy_full) - seen)
        if unknown_legacy:
            raise PlanError(f"FAIL_CI_IMPACT_LEGACY_FULL_UNKNOWN_CONTROL:{unknown_legacy}")

    for control in controls:
        unknown = sorted(set(control.dependencies) - seen)
        if unknown:
            raise PlanError(f"FAIL_CI_IMPACT_UNKNOWN_DEPENDENCY:{control.control_id}:{unknown}")
    return tuple(sorted(seen)), tuple(controls)


def _path_matches(path: str, matcher: Mapping[str, str]) -> bool:
    kind = matcher["kind"]
    value = matcher["value"]
    if kind == "prefix":
        return path.startswith(value)
    if kind == "exact":
        return path == value
    return False


def _material_matches(path: str, content: str | None, matcher: Mapping[str, str]) -> bool:
    kind = matcher["kind"]
    value = matcher["value"]
    if kind == "sql_regex":
        return content is not None and re.search(value, content) is not None
    if kind == "path_or_sql_regex":
        return re.search(value, path) is not None or (content is not None and re.search(value, content) is not None)
    return False


def _read_material(repo_root: Path, path: str, source_ref: str | None = None) -> tuple[str | None, dict[str, Any]]:
    if source_ref:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "show", f"{source_ref}:{path}"],
            check=False,
            capture_output=True,
        )
        if result.returncode != 0:
            return None, {"path": path, "state": "MISSING_OR_DELETED", "source_ref": source_ref}
        raw = result.stdout
    else:
        target = repo_root / path
        if not target.is_file():
            return None, {"path": path, "state": "MISSING_OR_DELETED"}
        raw = target.read_bytes()
    evidence: dict[str, Any] = {
        "path": path,
        "state": "PRESENT",
        "sha256": _sha(raw),
        "bytes": len(raw),
    }
    if source_ref:
        evidence["source_ref"] = source_ref
    if path.startswith("supabase/migrations/") and path.endswith(".sql"):
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise PlanError(f"FAIL_CI_MIGRATION_NON_UTF8:{path}") from exc
        evidence["kind"] = "SQL_MIGRATION"
        return content, evidence
    evidence["kind"] = "FILE"
    return None, evidence


def _plan_hash_payload(plan: Mapping[str, Any]) -> dict[str, Any]:
    missing = [key for key in PLAN_HASH_FIELDS if key not in plan]
    if missing:
        raise PlanError(f"FAIL_CI_PLAN_HASH_FIELDS_MISSING:{missing}")
    return {key: plan[key] for key in PLAN_HASH_FIELDS}


def compute_plan_sha256(plan: Mapping[str, Any]) -> str:
    return _sha(_canonical(_plan_hash_payload(plan)).encode("utf-8"))


def validate_plan_contract(plan: Mapping[str, Any]) -> None:
    if not isinstance(plan, Mapping) or plan.get("schema_version") != SCHEMA_VERSION:
        raise PlanError("FAIL_CI_PLAN_SCHEMA")
    if plan.get("applicability_authority") != "CHANGESET_GOVERNANCE_LF_V1+LF_CI_EXECUTION_PLAN_V2":
        raise PlanError("FAIL_CI_PLAN_APPLICABILITY_AUTHORITY")
    if plan.get("full_regression_semantics") != "CONSUME_GOVERNED_PLAN_ONLY":
        raise PlanError("FAIL_CI_PLAN_FULL_REGRESSION_SEMANTICS")
    if plan.get("carrier_regression_semantics") != "OBSERVABILITY_ONLY_NO_CONTROL_EXPANSION":
        raise PlanError("FAIL_CI_PLAN_CARRIER_REGRESSION_SEMANTICS")
    if plan.get("local_applicability_decisions") != 0:
        raise PlanError("FAIL_CI_PLAN_LOCAL_APPLICABILITY_DECISION")
    if plan.get("parallel_applicability_engine") != 0:
        raise PlanError("FAIL_CI_PLAN_PARALLEL_APPLICABILITY_ENGINE")
    if plan.get("run_everything") is not False:
        raise PlanError("FAIL_CI_PLAN_RUN_EVERYTHING")
    if plan.get("execution_ownership") != "CANONICAL_CARRIERS_ONLY":
        raise PlanError("FAIL_CI_PLAN_EXECUTION_OWNERSHIP")
    if plan.get("legacy_full_regression_registry_semantics") != "HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY":
        raise PlanError("FAIL_CI_PLAN_LEGACY_FULL_REGISTRY_SEMANTICS")

    required = plan.get("required_controls")
    universe = plan.get("control_universe")
    na_rows = plan.get("not_applicable_controls")
    carrier_controls = plan.get("carrier_controls")
    if not isinstance(required, list) or len(required) != len(set(required)) or required != sorted(required):
        raise PlanError("FAIL_CI_PLAN_REQUIRED_CONTROLS")
    if not isinstance(universe, list) or len(universe) != len(set(universe)) or universe != sorted(universe):
        raise PlanError("FAIL_CI_PLAN_CONTROL_UNIVERSE")
    if not isinstance(na_rows, list) or not isinstance(carrier_controls, Mapping):
        raise PlanError("FAIL_CI_PLAN_COVERAGE_SHAPE")

    not_applicable: list[str] = []
    for row in na_rows:
        if (
            not isinstance(row, Mapping)
            or set(row) != {"control_id", "carrier", "reason"}
            or row.get("reason") != "NO_TRIGGER_AND_NOT_IN_DEPENDENCY_CLOSURE"
        ):
            raise PlanError("FAIL_CI_PLAN_NOT_APPLICABLE_ROW")
        cid = row["control_id"]
        carrier = row["carrier"]
        if not isinstance(cid, str) or carrier not in CANONICAL_CARRIERS:
            raise PlanError("FAIL_CI_PLAN_NOT_APPLICABLE_ROW")
        not_applicable.append(cid)

    if sorted(required + not_applicable) != universe or set(required) & set(not_applicable):
        raise PlanError("FAIL_CI_PLAN_COVERAGE_PARTITION")
    if plan.get("coverage_complete") is not True:
        raise PlanError("FAIL_CI_PLAN_COVERAGE_INCOMPLETE")
    expected_decision = "NOT_APPLICABLE" if not required else "APPLY"
    if plan.get("applicability_decision") != expected_decision:
        raise PlanError("FAIL_CI_PLAN_APPLICABILITY_DECISION")

    flattened: list[str] = []
    for carrier, controls in carrier_controls.items():
        if carrier not in CANONICAL_CARRIERS:
            raise PlanError(f"FAIL_CI_PLAN_UNKNOWN_CARRIER:{carrier}")
        if not isinstance(controls, list) or controls != sorted(controls) or len(controls) != len(set(controls)):
            raise PlanError(f"FAIL_CI_PLAN_CARRIER_CONTROLS:{carrier}")
        flattened.extend(controls)
    if len(flattened) != len(set(flattened)):
        raise PlanError("FAIL_CI_PLAN_DUPLICATE_CONTROL_CARRIER")
    if sorted(flattened) != required:
        raise PlanError("FAIL_CI_PLAN_CARRIER_PARTITION")

    expected_sha = compute_plan_sha256(plan)
    if plan.get("plan_sha256") != expected_sha:
        raise PlanError("FAIL_CI_PLAN_SHA256")


def build_plan(
    *,
    changed_paths: Iterable[str],
    lane_required_controls: Iterable[str],
    lane_mode: str,
    repo_root: Path,
    force_full: bool = False,
    force_full_reason: str | None = None,
    source_ref: str | None = None,
    registry_path: Path = REGISTRY_PATH,
) -> dict[str, Any]:
    control_universe, controls = load_registry(registry_path)
    by_id = {c.control_id: c for c in controls}
    changed = tuple(sorted({p.strip() for p in changed_paths if isinstance(p, str) and p.strip()}))
    lane_controls = tuple(lane_required_controls)

    unresolved_modes = {
        "CLASSIFICATION_REQUIRED",
        "DEEP_SHARED_EMPTY_FAIL_CLOSED",
        "DEEP_SHARED_REGISTRY_INVALID",
    }
    if lane_mode in unresolved_modes or lane_mode.startswith("DEEP_SHARED_UNKNOWN"):
        raise PlanError(f"FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:{lane_mode}")
    if not changed and not lane_controls:
        raise PlanError("FAIL_CI_PLAN_EMPTY_WITHOUT_APPLICABILITY")

    unknown_lane_control = sorted(set(lane_controls) - set(control_universe))
    if unknown_lane_control:
        raise PlanError(f"FAIL_CI_PLAN_UNKNOWN_LANE_CONTROL:{unknown_lane_control}")

    authority_self_change = any(p.startswith(SELF_PREFIX) for p in changed)
    carrier_self_changes = tuple(sorted({CARRIER_SELF_PATHS[p] for p in changed if p in CARRIER_SELF_PATHS}))
    full_regression = bool(force_full or authority_self_change)
    full_reason = (
        force_full_reason
        if force_full
        else "CI_APPLICABILITY_AUTHORITY_SELF_CHANGE_VERIFICATION"
        if authority_self_change
        else None
    )
    carrier_regression = bool(carrier_self_changes)
    carrier_regression_reason = "CI_CARRIER_SELF_CHANGE_OBSERVABILITY" if carrier_regression else None

    required: set[str] = set(lane_controls)
    reason_map: dict[str, set[str]] = {cid: set() for cid in control_universe}
    for cid in lane_controls:
        reason_map[cid].add(f"CHANGESET_GOVERNANCE:{lane_mode}")

    material_evidence: list[dict[str, Any]] = []
    for path in changed:
        content, evidence = _read_material(repo_root, path, source_ref)
        matched_controls: set[str] = set()
        for control in controls:
            if any(_path_matches(path, m) for m in control.path_matchers):
                matched_controls.add(control.control_id)
                reason_map[control.control_id].add(f"PATH:{path}")
            if any(_material_matches(path, content, m) for m in control.material_matchers):
                matched_controls.add(control.control_id)
                reason_map[control.control_id].add(f"MATERIAL:{path}")
        required.update(matched_controls)
        evidence["matched_controls"] = sorted(matched_controls)
        if not matched_controls:
            evidence["applicability"] = "NO_LOCAL_TRIGGER"
        material_evidence.append(evidence)

    pending = list(required)
    while pending:
        cid = pending.pop()
        control = by_id.get(cid)
        if control is None:
            raise PlanError(f"FAIL_CI_PLAN_CONTROL_NOT_IN_REGISTRY:{cid}")
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
    carrier_controls: dict[str, list[str]] = {}
    for cid in required_sorted:
        carrier_controls.setdefault(by_id[cid].carrier, []).append(cid)
    for values in carrier_controls.values():
        values.sort()

    plan: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "router_capability": "CI_FAST_DEEP_LANE_ROUTER",
        "lane_mode": lane_mode,
        "applicability_authority": "CHANGESET_GOVERNANCE_LF_V1+LF_CI_EXECUTION_PLAN_V2",
        "applicability_decision": "NOT_APPLICABLE" if not required_sorted else "APPLY",
        "full_regression": full_regression,
        "full_regression_reason": full_reason,
        "full_regression_semantics": "CONSUME_GOVERNED_PLAN_ONLY",
        "carrier_regression": carrier_regression,
        "carrier_regression_reason": carrier_regression_reason,
        "carrier_regression_carriers": list(carrier_self_changes),
        "carrier_regression_semantics": "OBSERVABILITY_ONLY_NO_CONTROL_EXPANSION",
        "local_applicability_decisions": 0,
        "parallel_applicability_engine": 0,
        "run_everything": False,
        "execution_ownership": "CANONICAL_CARRIERS_ONLY",
        "legacy_full_regression_registry_semantics": "HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY",
        "changed_paths": list(changed),
        "material_evidence": material_evidence,
        "required_controls": required_sorted,
        "required_control_reasons": {cid: sorted(reason_map[cid]) for cid in required_sorted},
        "not_applicable_controls": not_applicable,
        "carrier_controls": dict(sorted(carrier_controls.items())),
        "control_universe": list(control_universe),
        "coverage_complete": len(required_sorted) + len(not_applicable) == len(control_universe),
    }
    if not plan["coverage_complete"]:
        raise PlanError("FAIL_CI_PLAN_COVERAGE_INCOMPLETE")
    plan["plan_sha256"] = compute_plan_sha256(plan)
    validate_plan_contract(plan)
    return plan
