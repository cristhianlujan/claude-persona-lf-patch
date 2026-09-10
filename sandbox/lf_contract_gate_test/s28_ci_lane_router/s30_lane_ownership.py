#!/usr/bin/env python3
"""Strict declarative S30 lane ownership registry for the CI applicability router."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

REGISTRY_VERSION = "S30_CI_LANE_OWNERSHIP_V1"
REGISTRY_NAMESPACE = "S30"
REGISTRY_PATH = Path(__file__).with_name("s30_lane_ownership_registry_v1.json")
S30_PATH_ROOT = "sandbox/lf_contract_gate_test/s30_"
S30_RECEIPT_ROOT = "sandbox/lf_contract_gate_test/receipts/s30_"
P0_EXACT_HEAD_EXTERNAL_PREFIX = "supabase/functions/lf-p0-exact-head-evidence-broker-v2/"
P0_EXACT_HEAD_EXTERNAL_EXACT = frozenset({
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v1.py",
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v2.py",
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_v2.json",
    "supabase/config.toml",
})
_REQUIRED_ENTRY_FIELDS = frozenset({
    "lane_id",
    "namespace",
    "ownership_class",
    "mode",
    "matchers",
    "migration_parity_required",
    "input_governance_parity_required",
    "p0_exact_head_external_required",
    "ci_router_selftest_required",
    "deep_shared",
    "known",
})
_ALLOWED_MATCHER_FIELDS = frozenset({"kind", "value"})
_LANE_ID_RE = re.compile(r"^S30-[A-Z0-9][A-Z0-9_-]*$")
_SYMBOL_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


class RegistryValidationError(ValueError):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(f"{code}:{detail}")
        self.code = code
        self.detail = detail


@dataclass(frozen=True)
class Matcher:
    kind: str
    value: str

    def matches(self, path: str) -> bool:
        if self.kind == "prefix":
            return path.startswith(self.value)
        return path == self.value


@dataclass(frozen=True)
class LaneOwnership:
    lane_id: str
    namespace: str
    ownership_class: str
    mode: str
    matchers: tuple[Matcher, ...]
    migration_parity_required: bool
    input_governance_parity_required: bool
    p0_exact_head_external_required: bool
    ci_router_selftest_required: bool
    deep_shared: bool
    known: bool


@dataclass(frozen=True)
class CompiledRegistry:
    version: str
    namespace: str
    lanes: tuple[LaneOwnership, ...]

    def match(self, path: str) -> LaneOwnership | None:
        matches = [lane for lane in self.lanes if any(m.matches(path) for m in lane.matchers)]
        if len(matches) > 1:
            raise RegistryValidationError("FAIL_S30_REGISTRY_RUNTIME_AMBIGUITY", path)
        return matches[0] if matches else None


def _require_bool(entry: Mapping[str, Any], field: str, lane_id: str) -> bool:
    value = entry[field]
    if type(value) is not bool:
        raise RegistryValidationError("FAIL_S30_REGISTRY_BOOLEAN", f"{lane_id}:{field}")
    return value


def _is_path_safe(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value or any(ch in value for ch in "*?[]"):
        return False
    parts = PurePosixPath(value).parts
    return bool(parts) and all(part not in {".", ".."} for part in parts)


def _validate_s30_matcher(kind: str, value: str, lane_id: str) -> Matcher:
    if kind not in {"prefix", "exact"}:
        raise RegistryValidationError("FAIL_S30_REGISTRY_MATCHER_KIND", f"{lane_id}:{kind}")
    if not isinstance(value, str) or not _is_path_safe(value):
        raise RegistryValidationError("FAIL_S30_REGISTRY_MATCHER_PATH", f"{lane_id}:{value!r}")
    if value.startswith(P0_EXACT_HEAD_EXTERNAL_PREFIX) or value in P0_EXACT_HEAD_EXTERNAL_EXACT:
        raise RegistryValidationError("FAIL_S30_REGISTRY_P0_OWNER_CAPTURE", f"{lane_id}:{value}")
    if not (value.startswith(S30_PATH_ROOT) or value.startswith(S30_RECEIPT_ROOT)):
        raise RegistryValidationError("FAIL_S30_REGISTRY_SCOPE_ESCAPE", f"{lane_id}:{value}")
    if value in {S30_PATH_ROOT, S30_RECEIPT_ROOT}:
        raise RegistryValidationError("FAIL_S30_REGISTRY_MATCHER_TOO_BROAD", f"{lane_id}:{value}")
    if kind == "prefix" and value.startswith(S30_PATH_ROOT) and not value.endswith("/"):
        raise RegistryValidationError("FAIL_S30_REGISTRY_PREFIX_SHAPE", f"{lane_id}:{value}")
    return Matcher(kind=kind, value=value)


def _matchers_overlap(a: Matcher, b: Matcher) -> bool:
    if a.kind == "exact" and b.kind == "exact":
        return a.value == b.value
    if a.kind == "prefix" and b.kind == "prefix":
        return a.value.startswith(b.value) or b.value.startswith(a.value)
    prefix, exact = (a, b) if a.kind == "prefix" else (b, a)
    return exact.value.startswith(prefix.value)


def compile_registry(data: Mapping[str, Any]) -> CompiledRegistry:
    if not isinstance(data, Mapping):
        raise RegistryValidationError("FAIL_S30_REGISTRY_ROOT", "root must be object")
    if data.get("registry_version") != REGISTRY_VERSION:
        raise RegistryValidationError("FAIL_S30_REGISTRY_VERSION", repr(data.get("registry_version")))
    if data.get("namespace") != REGISTRY_NAMESPACE:
        raise RegistryValidationError("FAIL_S30_REGISTRY_NAMESPACE", repr(data.get("namespace")))
    entries = data.get("lanes")
    if not isinstance(entries, list) or not entries:
        raise RegistryValidationError("FAIL_S30_REGISTRY_LANES", "lanes must be non-empty list")

    lanes: list[LaneOwnership] = []
    lane_ids: set[str] = set()
    ownership_classes: set[str] = set()
    all_matchers: list[tuple[str, Matcher]] = []

    for index, raw in enumerate(entries):
        if not isinstance(raw, Mapping):
            raise RegistryValidationError("FAIL_S30_REGISTRY_ENTRY", str(index))
        missing = _REQUIRED_ENTRY_FIELDS - set(raw)
        extra = set(raw) - _REQUIRED_ENTRY_FIELDS
        if missing:
            raise RegistryValidationError("FAIL_S30_REGISTRY_ENTRY_INCOMPLETE", f"{index}:{sorted(missing)}")
        if extra:
            raise RegistryValidationError("FAIL_S30_REGISTRY_ENTRY_EXTRA_FIELDS", f"{index}:{sorted(extra)}")

        lane_id = raw["lane_id"]
        namespace = raw["namespace"]
        ownership_class = raw["ownership_class"]
        mode = raw["mode"]
        if not isinstance(lane_id, str) or _LANE_ID_RE.fullmatch(lane_id) is None:
            raise RegistryValidationError("FAIL_S30_REGISTRY_LANE_ID", repr(lane_id))
        if lane_id in lane_ids:
            raise RegistryValidationError("FAIL_S30_REGISTRY_DUPLICATE_LANE", lane_id)
        lane_ids.add(lane_id)
        if namespace != REGISTRY_NAMESPACE:
            raise RegistryValidationError("FAIL_S30_REGISTRY_ENTRY_NAMESPACE", f"{lane_id}:{namespace!r}")
        if not isinstance(ownership_class, str) or _SYMBOL_RE.fullmatch(ownership_class) is None:
            raise RegistryValidationError("FAIL_S30_REGISTRY_OWNERSHIP_CLASS", f"{lane_id}:{ownership_class!r}")
        if ownership_class in ownership_classes:
            raise RegistryValidationError("FAIL_S30_REGISTRY_DUPLICATE_OWNERSHIP_CLASS", ownership_class)
        ownership_classes.add(ownership_class)
        if not isinstance(mode, str) or _SYMBOL_RE.fullmatch(mode) is None:
            raise RegistryValidationError("FAIL_S30_REGISTRY_MODE", f"{lane_id}:{mode!r}")

        raw_matchers = raw["matchers"]
        if not isinstance(raw_matchers, list) or not raw_matchers:
            raise RegistryValidationError("FAIL_S30_REGISTRY_MATCHERS", lane_id)
        matchers: list[Matcher] = []
        for raw_matcher in raw_matchers:
            if not isinstance(raw_matcher, Mapping) or set(raw_matcher) != _ALLOWED_MATCHER_FIELDS:
                raise RegistryValidationError("FAIL_S30_REGISTRY_MATCHER_FIELDS", lane_id)
            matcher = _validate_s30_matcher(raw_matcher["kind"], raw_matcher["value"], lane_id)
            for other_lane, other in all_matchers:
                if _matchers_overlap(matcher, other):
                    raise RegistryValidationError(
                        "FAIL_S30_REGISTRY_AMBIGUOUS_MATCHER",
                        f"{other_lane}:{other.value}<->{lane_id}:{matcher.value}",
                    )
            all_matchers.append((lane_id, matcher))
            matchers.append(matcher)

        migration = _require_bool(raw, "migration_parity_required", lane_id)
        input_gov = _require_bool(raw, "input_governance_parity_required", lane_id)
        p0_external = _require_bool(raw, "p0_exact_head_external_required", lane_id)
        selftest = _require_bool(raw, "ci_router_selftest_required", lane_id)
        deep_shared = _require_bool(raw, "deep_shared", lane_id)
        known = _require_bool(raw, "known", lane_id)
        if known and deep_shared:
            raise RegistryValidationError("FAIL_S30_REGISTRY_KNOWN_DEEP_SHARED", lane_id)
        if not known and not (migration and input_gov and p0_external and deep_shared):
            raise RegistryValidationError("FAIL_S30_REGISTRY_UNKNOWN_PERMISSIVE", lane_id)

        lanes.append(
            LaneOwnership(
                lane_id=lane_id,
                namespace=namespace,
                ownership_class=ownership_class,
                mode=mode,
                matchers=tuple(matchers),
                migration_parity_required=migration,
                input_governance_parity_required=input_gov,
                p0_exact_head_external_required=p0_external,
                ci_router_selftest_required=selftest,
                deep_shared=deep_shared,
                known=known,
            )
        )
    return CompiledRegistry(version=REGISTRY_VERSION, namespace=REGISTRY_NAMESPACE, lanes=tuple(lanes))


@lru_cache(maxsize=1)
def load_registry() -> CompiledRegistry:
    try:
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RegistryValidationError("FAIL_S30_REGISTRY_LOAD", str(exc)) from exc
    return compile_registry(data)
