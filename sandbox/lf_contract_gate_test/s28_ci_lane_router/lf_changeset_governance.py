#!/usr/bin/env python3
"""REPORT_ONLY changeset integrity for the existing LF CI lane router.

Policy paths and family/control mappings live in lf_change_family_registry_v1.json.
This helper classifies fixed families, consumes at most one per-PR manifest, and
returns deterministic findings without blocking CI in V1 REPORT_ONLY mode.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping

REGISTRY_VERSION = "LF_CHANGE_FAMILY_REGISTRY_V1"
SCHEMA_VERSION = "lf-changeset-governance/v1"
REGISTRY_PATH = Path(__file__).with_name("lf_change_family_registry_v1.json")
_SYMBOL_RE = re.compile(r"^[A-Z][A-Z0-9_-]*$")
_SOLUTION_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$")


class ChangeFamilyRegistryError(ValueError):
    pass


@dataclass(frozen=True)
class Matcher:
    kind: str
    value: str

    def matches(self, path: str) -> bool:
        return path == self.value if self.kind == "exact" else path.startswith(self.value)


@dataclass(frozen=True)
class FixedFamily:
    family: str
    matchers: tuple[Matcher, ...]


@dataclass(frozen=True)
class CompiledRegistry:
    fixed_families: tuple[FixedFamily, ...]
    manifest_families: frozenset[str]
    family_controls: Mapping[str, tuple[str, ...]]

    def fixed_family(self, path: str) -> str | None:
        matches = [row.family for row in self.fixed_families if any(m.matches(path) for m in row.matchers)]
        if len(matches) > 1:
            raise ChangeFamilyRegistryError(f"FAIL_CHANGESET_FIXED_FAMILY_AMBIGUITY:{path}")
        return matches[0] if matches else None


def _safe_path(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value or any(ch in value for ch in "*?[]"):
        return False
    parts = PurePosixPath(value).parts
    return bool(parts) and all(part not in {".", ".."} for part in parts)


def _overlap(a: Matcher, b: Matcher) -> bool:
    if a.kind == b.kind == "exact":
        return a.value == b.value
    if a.kind == b.kind == "prefix":
        return a.value.startswith(b.value) or b.value.startswith(a.value)
    prefix, exact = (a, b) if a.kind == "prefix" else (b, a)
    return exact.value.startswith(prefix.value)


def compile_registry(data: Mapping[str, Any]) -> CompiledRegistry:
    if not isinstance(data, Mapping) or set(data) != {
        "registry_version", "fixed_families", "manifest_families", "family_controls"
    }:
        raise ChangeFamilyRegistryError("FAIL_CHANGESET_REGISTRY_FIELDS")
    if data.get("registry_version") != REGISTRY_VERSION:
        raise ChangeFamilyRegistryError("FAIL_CHANGESET_REGISTRY_VERSION")

    raw_fixed = data.get("fixed_families")
    raw_manifest = data.get("manifest_families")
    raw_controls = data.get("family_controls")
    if not isinstance(raw_fixed, list) or not raw_fixed:
        raise ChangeFamilyRegistryError("FAIL_CHANGESET_FIXED_FAMILIES")
    if not isinstance(raw_manifest, list) or not raw_manifest:
        raise ChangeFamilyRegistryError("FAIL_CHANGESET_MANIFEST_FAMILIES")
    if not isinstance(raw_controls, Mapping):
        raise ChangeFamilyRegistryError("FAIL_CHANGESET_FAMILY_CONTROLS")

    manifest_families: set[str] = set()
    for family in raw_manifest:
        if not isinstance(family, str) or _SYMBOL_RE.fullmatch(family) is None:
            raise ChangeFamilyRegistryError("FAIL_CHANGESET_MANIFEST_FAMILY_ID")
        if family in manifest_families:
            raise ChangeFamilyRegistryError(f"FAIL_CHANGESET_MANIFEST_FAMILY_DUPLICATE:{family}")
        manifest_families.add(family)

    fixed_rows: list[FixedFamily] = []
    family_names: set[str] = set()
    seen_matchers: list[tuple[str, Matcher]] = []
    for raw in raw_fixed:
        if not isinstance(raw, Mapping) or set(raw) != {"family", "matchers"}:
            raise ChangeFamilyRegistryError("FAIL_CHANGESET_FIXED_FAMILY_FIELDS")
        family = raw.get("family")
        matchers = raw.get("matchers")
        if not isinstance(family, str) or _SYMBOL_RE.fullmatch(family) is None or family in family_names:
            raise ChangeFamilyRegistryError("FAIL_CHANGESET_FIXED_FAMILY_ID")
        if not isinstance(matchers, list) or not matchers:
            raise ChangeFamilyRegistryError(f"FAIL_CHANGESET_FIXED_FAMILY_MATCHERS:{family}")
        family_names.add(family)
        compiled: list[Matcher] = []
        for raw_matcher in matchers:
            if not isinstance(raw_matcher, Mapping) or set(raw_matcher) != {"kind", "value"}:
                raise ChangeFamilyRegistryError("FAIL_CHANGESET_MATCHER_FIELDS")
            kind = raw_matcher.get("kind")
            value = raw_matcher.get("value")
            if kind not in {"prefix", "exact"} or not isinstance(value, str) or not _safe_path(value):
                raise ChangeFamilyRegistryError(f"FAIL_CHANGESET_MATCHER:{family}")
            matcher = Matcher(kind=kind, value=value)
            for other_family, other in seen_matchers:
                if _overlap(matcher, other):
                    raise ChangeFamilyRegistryError(
                        f"FAIL_CHANGESET_FIXED_FAMILY_OVERLAP:{other_family}:{family}"
                    )
            seen_matchers.append((family, matcher))
            compiled.append(matcher)
        fixed_rows.append(FixedFamily(family=family, matchers=tuple(compiled)))

    all_families = family_names | manifest_families
    if set(raw_controls) != all_families:
        raise ChangeFamilyRegistryError("FAIL_CHANGESET_FAMILY_CONTROL_COVERAGE")
    controls: dict[str, tuple[str, ...]] = {}
    for family, raw in raw_controls.items():
        if not isinstance(raw, list) or any(
            not isinstance(value, str) or _SYMBOL_RE.fullmatch(value) is None for value in raw
        ):
            raise ChangeFamilyRegistryError(f"FAIL_CHANGESET_FAMILY_CONTROL_VALUE:{family}")
        if len(raw) != len(set(raw)):
            raise ChangeFamilyRegistryError(f"FAIL_CHANGESET_FAMILY_CONTROL_DUPLICATE:{family}")
        controls[str(family)] = tuple(sorted(raw))

    return CompiledRegistry(
        fixed_families=tuple(fixed_rows),
        manifest_families=frozenset(manifest_families),
        family_controls=controls,
    )


@lru_cache(maxsize=1)
def load_registry() -> CompiledRegistry:
    return compile_registry(json.loads(REGISTRY_PATH.read_text(encoding="utf-8")))


def _finding(code: str, **detail: Any) -> dict[str, Any]:
    return {"code": code, **detail}


def evaluate(
    *,
    repo_root: Path,
    changed_paths: Iterable[str],
    registry: CompiledRegistry | None = None,
) -> dict[str, Any]:
    reg = registry or load_registry()
    changed = tuple(sorted({str(p).strip() for p in changed_paths if str(p).strip()}))
    family_by_path: dict[str, str] = {}
    findings: list[dict[str, Any]] = []

    for path in changed:
        fixed = reg.fixed_family(path)
        if fixed:
            family_by_path[path] = fixed

    manifest_paths = [p for p in changed if family_by_path.get(p) == "CHANGESET_MANIFEST"]
    solution_ref: str | None = None
    manifest_declared: dict[str, str] = {}

    if len(manifest_paths) > 1:
        findings.append(_finding("FAIL_CHANGESET_MULTIPLE_SOLUTIONS", manifests=manifest_paths))
    elif len(manifest_paths) == 1:
        manifest_path = manifest_paths[0]
        try:
            payload = json.loads((repo_root / manifest_path).read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            findings.append(_finding("FAIL_CHANGESET_MANIFEST_READ", path=manifest_path, error=type(exc).__name__))
            payload = None
        if isinstance(payload, Mapping):
            if set(payload) != {"solution_ref", "paths"}:
                findings.append(_finding("FAIL_CHANGESET_MANIFEST_FIELDS", path=manifest_path))
            else:
                raw_ref = payload.get("solution_ref")
                raw_paths = payload.get("paths")
                if not isinstance(raw_ref, str) or _SOLUTION_REF_RE.fullmatch(raw_ref) is None:
                    findings.append(_finding("FAIL_CHANGESET_SOLUTION_REF", path=manifest_path))
                else:
                    solution_ref = raw_ref
                    if Path(manifest_path).stem != raw_ref:
                        findings.append(_finding(
                            "FAIL_CHANGESET_SOLUTION_REF_FILENAME",
                            path=manifest_path,
                            solution_ref=raw_ref,
                        ))
                if not isinstance(raw_paths, Mapping):
                    findings.append(_finding("FAIL_CHANGESET_MANIFEST_PATHS", path=manifest_path))
                else:
                    for raw_path, raw_family in raw_paths.items():
                        if not isinstance(raw_path, str) or not _safe_path(raw_path):
                            findings.append(_finding("FAIL_CHANGESET_DECLARED_PATH", path=repr(raw_path)))
                            continue
                        if not isinstance(raw_family, str) or _SYMBOL_RE.fullmatch(raw_family) is None:
                            findings.append(_finding("FAIL_CHANGESET_DECLARED_FAMILY", path=raw_path))
                            continue
                        if raw_path not in changed:
                            findings.append(_finding("FAIL_CHANGESET_PATH_NOT_IN_DIFF", path=raw_path))
                            continue
                        fixed = reg.fixed_family(raw_path)
                        if fixed is not None:
                            if raw_family != fixed:
                                findings.append(_finding(
                                    "FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE",
                                    path=raw_path,
                                    fixed_family=fixed,
                                    declared_family=raw_family,
                                ))
                            manifest_declared[raw_path] = fixed
                            continue
                        if raw_family not in reg.manifest_families:
                            findings.append(_finding(
                                "FAIL_CHANGESET_UNKNOWN_MANIFEST_FAMILY",
                                path=raw_path,
                                declared_family=raw_family,
                            ))
                            continue
                        manifest_declared[raw_path] = raw_family
                        family_by_path[raw_path] = raw_family

    classification_required: list[str] = []
    for path in changed:
        if path not in family_by_path:
            classification_required.append(path)
            if manifest_paths:
                findings.append(_finding("FAIL_CHANGESET_UNDECLARED_PATH", path=path))

    result = "PASS"
    if findings:
        result = "PR_INTEGRITY_FINDINGS"
    elif classification_required:
        result = "CLASSIFICATION_REQUIRED"

    return {
        "schema_version": SCHEMA_VERSION,
        "mode": "REPORT_ONLY",
        "result": result,
        "would_block": False,
        "manifest_count": len(manifest_paths),
        "manifest_paths": manifest_paths,
        "solution_ref": solution_ref,
        "family_by_path": dict(sorted(family_by_path.items())),
        "family_controls": {key: list(value) for key, value in sorted(reg.family_controls.items())},
        "classification_required_paths": classification_required,
        "findings": findings,
    }
