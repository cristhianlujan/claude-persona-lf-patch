#!/usr/bin/env python3
"""Deterministic PR-integrity evaluator consumed by CI_FAST_DEEP_LANE_ROUTER.

REPORT_ONLY classifies one solution without judging semantic quality. Fixed
families are declarative and cannot be overridden by a per-PR manifest.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping

REGISTRY_PATH = Path(__file__).with_name("lf_change_family_registry_v1.json")
REGISTRY_VERSION = "LF_CHANGE_FAMILY_REGISTRY_V1"
FAMILY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
SOLUTION_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


class ChangesetIntegrityError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class FixedFamily:
    family: str
    kind: str
    value: str

    def matches(self, path: str) -> bool:
        return path == self.value if self.kind == "exact" else path.startswith(self.value)


@dataclass(frozen=True)
class FamilyRegistry:
    fixed: tuple[FixedFamily, ...]
    controls: Mapping[str, tuple[str, ...]]

    def family_for(self, path: str) -> str | None:
        matches = [item.family for item in self.fixed if item.matches(path)]
        if len(matches) > 1:
            raise ChangesetIntegrityError("FAIL_CHANGESET_FIXED_FAMILY_AMBIGUOUS", path)
        return matches[0] if matches else None


def _safe_path(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value or any(c in value for c in "*?[]"):
        return False
    return all(part not in {".", ".."} for part in PurePosixPath(value).parts)


def compile_family_registry(data: Mapping[str, Any]) -> FamilyRegistry:
    if not isinstance(data, Mapping) or data.get("registry_version") != REGISTRY_VERSION:
        raise ChangesetIntegrityError("FAIL_CHANGESET_FAMILY_REGISTRY_VERSION")
    raw = data.get("fixed_families")
    controls = data.get("family_controls")
    if not isinstance(raw, list) or not isinstance(controls, Mapping):
        raise ChangesetIntegrityError("FAIL_CHANGESET_FAMILY_REGISTRY_SHAPE")
    fixed: list[FixedFamily] = []
    seen: set[str] = set()
    for row in raw:
        if not isinstance(row, Mapping) or set(row) != {"family", "kind", "value"}:
            raise ChangesetIntegrityError("FAIL_CHANGESET_FIXED_FAMILY_ENTRY")
        family, kind, value = row["family"], row["kind"], row["value"]
        if not isinstance(family, str) or FAMILY_RE.fullmatch(family) is None or family in seen:
            raise ChangesetIntegrityError("FAIL_CHANGESET_FIXED_FAMILY_ID", str(family))
        if kind not in {"prefix", "exact"} or not isinstance(value, str) or not _safe_path(value):
            raise ChangesetIntegrityError("FAIL_CHANGESET_FIXED_FAMILY_MATCHER", str(value))
        seen.add(family)
        fixed.append(FixedFamily(family, kind, value))
    compiled_controls: dict[str, tuple[str, ...]] = {}
    for family, values in controls.items():
        if family not in seen or not isinstance(values, list) or any(not isinstance(v, str) for v in values):
            raise ChangesetIntegrityError("FAIL_CHANGESET_FAMILY_CONTROLS", str(family))
        compiled_controls[family] = tuple(sorted(set(values)))
    return FamilyRegistry(tuple(fixed), compiled_controls)


@lru_cache(maxsize=1)
def load_family_registry() -> FamilyRegistry:
    return compile_family_registry(json.loads(REGISTRY_PATH.read_text(encoding="utf-8")))


def _manifest_paths(paths: Iterable[str], registry: FamilyRegistry) -> list[str]:
    return sorted({
        p for p in paths
        if PurePosixPath(p).suffix == ".json" and registry.family_for(p) == "CHANGESET_MANIFEST"
    })


def parse_manifest(data: Mapping[str, Any], *, manifest_path: str) -> tuple[str, dict[str, str]]:
    if not isinstance(data, Mapping) or set(data) != {"solution_ref", "paths"}:
        raise ChangesetIntegrityError("FAIL_CHANGESET_MANIFEST_SHAPE", manifest_path)
    solution_ref = data.get("solution_ref")
    mapping = data.get("paths")
    path = PurePosixPath(manifest_path)
    if (
        not isinstance(solution_ref, str)
        or SOLUTION_REF_RE.fullmatch(solution_ref) is None
        or path.suffix != ".json"
        or path.stem != solution_ref
    ):
        raise ChangesetIntegrityError("FAIL_CHANGESET_SOLUTION_REF", manifest_path)
    if not isinstance(mapping, Mapping):
        raise ChangesetIntegrityError("FAIL_CHANGESET_MANIFEST_PATHS", manifest_path)
    result: dict[str, str] = {}
    for path, family in mapping.items():
        if not isinstance(path, str) or not _safe_path(path) or not isinstance(family, str) or FAMILY_RE.fullmatch(family) is None:
            raise ChangesetIntegrityError("FAIL_CHANGESET_MANIFEST_PATH_ENTRY", str(path))
        result[path] = family
    return solution_ref, result


def evaluate_pr_integrity(
    paths: Iterable[str],
    *,
    manifest_data: Mapping[str, Any] | None = None,
    registry: FamilyRegistry | None = None,
) -> dict[str, Any]:
    changed = tuple(sorted({p.strip() for p in paths if isinstance(p, str) and p.strip()}))
    reg = registry or load_family_registry()
    manifests = _manifest_paths(changed, reg)
    if len(manifests) > 1:
        raise ChangesetIntegrityError("FAIL_CHANGESET_MULTIPLE_SOLUTIONS", ",".join(manifests))
    manifest_path = manifests[0] if manifests else None
    if manifest_data is not None and manifest_path is None:
        raise ChangesetIntegrityError("FAIL_CHANGESET_MANIFEST_NOT_IN_DIFF")
    solution_ref = None
    declared: dict[str, str] = {}
    if manifest_path is not None:
        if manifest_data is None:
            return {"mode": "REPORT_ONLY", "classification_required": True, "solution_ref": None, "families": {}, "violations": ["MANIFEST_CONTENT_REQUIRED"]}
        solution_ref, declared = parse_manifest(manifest_data, manifest_path=manifest_path)

    families: dict[str, str] = {}
    violations: list[str] = []
    for path in changed:
        fixed = reg.family_for(path)
        declared_family = declared.get(path)
        if fixed is not None:
            families[path] = fixed
            if declared_family is not None and declared_family != fixed:
                raise ChangesetIntegrityError("FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE", f"{path}:{fixed}->{declared_family}")
        elif declared_family is not None:
            families[path] = declared_family
        else:
            violations.append(f"UNDECLARED_PATH:{path}")
    extras = sorted(set(declared) - set(changed))
    violations.extend(f"DECLARED_PATH_NOT_IN_DIFF:{path}" for path in extras)
    return {
        "mode": "REPORT_ONLY",
        "classification_required": bool(violations),
        "solution_ref": solution_ref,
        "families": families,
        "violations": violations,
    }
