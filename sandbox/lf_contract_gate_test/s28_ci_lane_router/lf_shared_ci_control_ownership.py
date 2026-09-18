#!/usr/bin/env python3
"""Strict declarative ownership for exact shared LF CI self-test controls.

This registry removes the need to patch lf_ci_lane_router.py whenever a new
shared CI self-test control must be classified. V1 intentionally supports exact
paths and one non-specialized self-test profile only: unknown siblings,
lookalikes, migrations and external P0 ownership remain fail-closed or governed
by their existing specialized authorities.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

REGISTRY_VERSION = "LF_SHARED_CI_CONTROL_OWNERSHIP_V1"
REGISTRY_PATH = Path(__file__).with_name("lf_shared_ci_control_ownership_registry_v1.json")
_REQUIRED_FIELDS = frozenset({
    "control_id",
    "path",
    "migration_parity_required",
    "input_governance_parity_required",
    "ci_router_selftest_required",
    "p0_exact_head_external_required",
    "deep_shared",
})
_OPTIONAL_FIELDS = frozenset({"required_controls"})
_SYMBOL_RE = re.compile(r"^[A-Z][A-Z0-9_-]*$")


class SharedRegistryValidationError(ValueError):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(f"{code}:{detail}")
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class SharedControlOwnership:
    control_id: str
    path: str
    migration_parity_required: bool
    input_governance_parity_required: bool
    ci_router_selftest_required: bool
    p0_exact_head_external_required: bool
    deep_shared: bool
    required_controls: tuple[str, ...]


@dataclass(frozen=True)
class CompiledSharedRegistry:
    version: str
    controls: tuple[SharedControlOwnership, ...]

    def match(self, path: str) -> SharedControlOwnership | None:
        for control in self.controls:
            if control.path == path:
                return control
        return None


def _is_path_safe(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value or any(ch in value for ch in "*?[]"):
        return False
    parts = PurePosixPath(value).parts
    return bool(parts) and all(part not in {".", ".."} for part in parts)


def _require_bool(raw: Mapping[str, Any], field: str, control_id: str) -> bool:
    value = raw[field]
    if type(value) is not bool:
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_BOOLEAN", f"{control_id}:{field}")
    return value


def _required_controls(raw: Mapping[str, Any], control_id: str, legacy: tuple[str, ...]) -> tuple[str, ...]:
    value = raw.get("required_controls")
    if value is None:
        return legacy
    if not isinstance(value, list):
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_REQUIRED_CONTROLS", f"{control_id}:not_list")
    if any(not isinstance(item, str) or _SYMBOL_RE.fullmatch(item) is None for item in value):
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_REQUIRED_CONTROL_ID", control_id)
    if len(value) != len(set(value)):
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_REQUIRED_CONTROL_DUPLICATE", control_id)
    canonical = tuple(sorted(value))
    for required in legacy:
        if required not in canonical:
            raise SharedRegistryValidationError(
                "FAIL_LF_SHARED_REGISTRY_REQUIRED_CONTROL_LEGACY_MISMATCH",
                f"{control_id}:{required}",
            )
    return canonical


def compile_shared_registry(data: Mapping[str, Any]) -> CompiledSharedRegistry:
    if not isinstance(data, Mapping):
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_ROOT", "root must be object")
    if set(data) != {"registry_version", "controls"}:
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_FIELDS", repr(sorted(data)))
    if data.get("registry_version") != REGISTRY_VERSION:
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_VERSION", repr(data.get("registry_version")))

    entries = data.get("controls")
    if not isinstance(entries, list) or not entries:
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_CONTROLS", "controls must be non-empty list")

    controls: list[SharedControlOwnership] = []
    control_ids: set[str] = set()
    paths: set[str] = set()
    for index, raw in enumerate(entries):
        if not isinstance(raw, Mapping):
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_ENTRY", str(index))
        missing = _REQUIRED_FIELDS - set(raw)
        extra = set(raw) - (_REQUIRED_FIELDS | _OPTIONAL_FIELDS)
        if missing:
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_ENTRY_INCOMPLETE", f"{index}:{sorted(missing)}")
        if extra:
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_ENTRY_EXTRA_FIELDS", f"{index}:{sorted(extra)}")

        control_id = raw["control_id"]
        path = raw["path"]
        if not isinstance(control_id, str) or _SYMBOL_RE.fullmatch(control_id) is None:
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_CONTROL_ID", repr(control_id))
        if control_id in control_ids:
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_DUPLICATE_CONTROL", control_id)
        control_ids.add(control_id)
        if not isinstance(path, str) or not _is_path_safe(path):
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_PATH", f"{control_id}:{path!r}")
        if path in paths:
            raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_DUPLICATE_PATH", path)
        paths.add(path)

        migration = _require_bool(raw, "migration_parity_required", control_id)
        input_gov = _require_bool(raw, "input_governance_parity_required", control_id)
        selftest = _require_bool(raw, "ci_router_selftest_required", control_id)
        p0_external = _require_bool(raw, "p0_exact_head_external_required", control_id)
        deep_shared = _require_bool(raw, "deep_shared", control_id)
        if migration or input_gov or not selftest or p0_external or deep_shared:
            raise SharedRegistryValidationError(
                "FAIL_LF_SHARED_REGISTRY_PROFILE",
                f"{control_id}:V1_REQUIRES_EXACT_NON_SPECIALIZED_SELFTEST",
            )
        required_controls = _required_controls(raw, control_id, ("CI_ROUTER_SELFTEST",))

        controls.append(
            SharedControlOwnership(
                control_id=control_id,
                path=path,
                migration_parity_required=migration,
                input_governance_parity_required=input_gov,
                ci_router_selftest_required=selftest,
                p0_exact_head_external_required=p0_external,
                deep_shared=deep_shared,
                required_controls=required_controls,
            )
        )

    return CompiledSharedRegistry(version=REGISTRY_VERSION, controls=tuple(controls))


@lru_cache(maxsize=1)
def load_shared_registry() -> CompiledSharedRegistry:
    try:
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SharedRegistryValidationError("FAIL_LF_SHARED_REGISTRY_LOAD", str(exc)) from exc
    return compile_shared_registry(data)
