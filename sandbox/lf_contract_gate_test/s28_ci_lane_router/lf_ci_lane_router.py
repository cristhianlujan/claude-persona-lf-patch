#!/usr/bin/env python3
"""Fail-closed applicability router for specialized LF contract-check lanes.

Product ownership and exact shared-control ownership are declarative. Unknown,
ambiguous or invalid ownership remains fail-closed instead of granting a
specialized N/A.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Iterable, Mapping, Any

_OWNERSHIP_PATH = Path(__file__).with_name("lf_product_lane_ownership.py")
_OWNERSHIP_SPEC = importlib.util.spec_from_file_location("lf_product_lane_ownership", _OWNERSHIP_PATH)
if _OWNERSHIP_SPEC is None or _OWNERSHIP_SPEC.loader is None:
    raise ImportError(f"cannot load LF product ownership helper: {_OWNERSHIP_PATH}")
_OWNERSHIP = importlib.util.module_from_spec(_OWNERSHIP_SPEC)
sys.modules[_OWNERSHIP_SPEC.name] = _OWNERSHIP
_OWNERSHIP_SPEC.loader.exec_module(_OWNERSHIP)
CompiledRegistry = _OWNERSHIP.CompiledRegistry
RegistryValidationError = _OWNERSHIP.RegistryValidationError
compile_registry = _OWNERSHIP.compile_registry
load_registry = _OWNERSHIP.load_registry

_SHARED_OWNERSHIP_PATH = Path(__file__).with_name("lf_shared_ci_control_ownership.py")
_SHARED_OWNERSHIP_SPEC = importlib.util.spec_from_file_location("lf_shared_ci_control_ownership", _SHARED_OWNERSHIP_PATH)
if _SHARED_OWNERSHIP_SPEC is None or _SHARED_OWNERSHIP_SPEC.loader is None:
    raise ImportError(f"cannot load LF shared control ownership helper: {_SHARED_OWNERSHIP_PATH}")
_SHARED_OWNERSHIP = importlib.util.module_from_spec(_SHARED_OWNERSHIP_SPEC)
sys.modules[_SHARED_OWNERSHIP_SPEC.name] = _SHARED_OWNERSHIP
_SHARED_OWNERSHIP_SPEC.loader.exec_module(_SHARED_OWNERSHIP)
CompiledSharedRegistry = _SHARED_OWNERSHIP.CompiledSharedRegistry
SharedRegistryValidationError = _SHARED_OWNERSHIP.SharedRegistryValidationError
compile_shared_registry = _SHARED_OWNERSHIP.compile_shared_registry
load_shared_registry = _SHARED_OWNERSHIP.load_shared_registry

MIGRATION_PREFIX = "supabase/migrations/"
MIGRATION_VALIDATOR = "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
MIGRATION_TRANSPORT_TEST = "sandbox/lf_contract_gate_test/test_lf_migration_source_parity_transport.py"
INPUT_GOV_VALIDATOR = "sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py"
CI_ROUTER_PREFIX = "sandbox/lf_contract_gate_test/s28_ci_lane_router/"
P0_EXACT_HEAD_EXTERNAL_PREFIX = "supabase/functions/lf-p0-exact-head-evidence-broker-v2/"
P0_EXACT_HEAD_EXTERNAL_EXACT = frozenset({
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v1.py",
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v2.py",
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_v2.json",
    "supabase/config.toml",
})

CONTROL_MIGRATION_SOURCE_PARITY = "MIGRATION_SOURCE_PARITY"
CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY = "INPUT_GOVERNANCE_MIGRATION_PARITY"
CONTROL_CI_ROUTER_SELFTEST = "CI_ROUTER_SELFTEST"
CONTROL_P0_EXACT_HEAD_EXTERNAL = "P0_EXACT_HEAD_EXTERNAL"
FAIL_CLOSED_REQUIRED_CONTROLS = tuple(sorted({
    CONTROL_MIGRATION_SOURCE_PARITY,
    CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY,
    CONTROL_CI_ROUTER_SELFTEST,
    CONTROL_P0_EXACT_HEAD_EXTERNAL,
}))
_CONTROL_CODE_RE = re.compile(r"^[A-Z][A-Z0-9_-]*$")


def _canonical_required_controls(values: Iterable[str]) -> tuple[str, ...]:
    raw = tuple(values)
    if any(
        not isinstance(value, str)
        or not value
        or value.strip() != value
        or _CONTROL_CODE_RE.fullmatch(value) is None
        for value in raw
    ):
        raise ValueError("FAIL_LF_REQUIRED_CONTROL_ID")
    if len(raw) != len(set(raw)):
        raise ValueError("FAIL_LF_REQUIRED_CONTROL_DUPLICATE")
    return tuple(sorted(raw))


def _legacy_required_controls(
    *,
    migration_parity_required: bool,
    input_governance_parity_required: bool,
    ci_router_selftest_required: bool,
    p0_exact_head_external_required: bool,
) -> tuple[str, ...]:
    controls: list[str] = []
    if migration_parity_required:
        controls.append(CONTROL_MIGRATION_SOURCE_PARITY)
    if input_governance_parity_required:
        controls.append(CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY)
    if ci_router_selftest_required:
        controls.append(CONTROL_CI_ROUTER_SELFTEST)
    if p0_exact_head_external_required:
        controls.append(CONTROL_P0_EXACT_HEAD_EXTERNAL)
    return tuple(sorted(controls))

# Deliberately excludes the broad sandbox/lf_contract_gate_test/ prefix. Unknown
# validator surfaces in that tree must remain fail-closed unless explicitly bound.
KNOWN_SHARED_PREFIXES = (
    "sandbox/no_bypass_judge_profile_card_skill/",
    "skills/",
    "profiles/",
    "cards/",
    "adapters/",
    "gobernanza/",
    "services/profile_runtime_api/",
    "docs/",
    "claude/",
    ".claude/",
    "ops/",
)


class LaneDecision:
    __slots__ = (
        "mode",
        "required_controls",
        "migration_parity_required",
        "input_governance_parity_required",
        "ci_router_selftest_required",
        "p0_exact_head_external_required",
        "deep_shared",
        "reasons",
    )

    def __init__(
        self,
        *,
        mode: str,
        migration_parity_required: bool,
        input_governance_parity_required: bool,
        ci_router_selftest_required: bool,
        p0_exact_head_external_required: bool,
        deep_shared: bool,
        reasons: tuple[str, ...],
        required_controls: Iterable[str] | None = None,
    ) -> None:
        legacy = _legacy_required_controls(
            migration_parity_required=migration_parity_required,
            input_governance_parity_required=input_governance_parity_required,
            ci_router_selftest_required=ci_router_selftest_required,
            p0_exact_head_external_required=p0_exact_head_external_required,
        )
        canonical = legacy if required_controls is None else _canonical_required_controls(required_controls)

        legacy_expectations = {
            CONTROL_MIGRATION_SOURCE_PARITY: migration_parity_required,
            CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY: input_governance_parity_required,
            CONTROL_CI_ROUTER_SELFTEST: ci_router_selftest_required,
            CONTROL_P0_EXACT_HEAD_EXTERNAL: p0_exact_head_external_required,
        }
        for control_code, expected in legacy_expectations.items():
            if (control_code in canonical) is not expected:
                raise ValueError(f"FAIL_LF_REQUIRED_CONTROL_LEGACY_MISMATCH:{control_code}")

        self.mode = mode
        self.required_controls = canonical
        self.migration_parity_required = CONTROL_MIGRATION_SOURCE_PARITY in canonical
        self.input_governance_parity_required = CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY in canonical
        self.ci_router_selftest_required = CONTROL_CI_ROUTER_SELFTEST in canonical
        self.p0_exact_head_external_required = CONTROL_P0_EXACT_HEAD_EXTERNAL in canonical
        self.deep_shared = deep_shared
        self.reasons = reasons

    def requires(self, control_code: str) -> bool:
        return control_code in self.required_controls

    def __repr__(self) -> str:
        return (
            "LaneDecision("
            f"mode={self.mode!r}, required_controls={self.required_controls!r}, "
            f"migration_parity_required={self.migration_parity_required!r}, "
            f"input_governance_parity_required={self.input_governance_parity_required!r}, "
            f"ci_router_selftest_required={self.ci_router_selftest_required!r}, "
            f"p0_exact_head_external_required={self.p0_exact_head_external_required!r}, "
            f"deep_shared={self.deep_shared!r}, reasons={self.reasons!r})"
        )

    def to_dict(self) -> dict:
        return {
            "mode": self.mode,
            "required_controls": list(self.required_controls),
            "migration_parity_required": self.migration_parity_required,
            "input_governance_parity_required": self.input_governance_parity_required,
            "ci_router_selftest_required": self.ci_router_selftest_required,
            "p0_exact_head_external_required": self.p0_exact_head_external_required,
            "deep_shared": self.deep_shared,
            "reasons": list(self.reasons),
        }

def _fail_closed(mode: str, reason: str) -> LaneDecision:
    return LaneDecision(
        mode=mode,
        migration_parity_required=True,
        input_governance_parity_required=True,
        ci_router_selftest_required=True,
        p0_exact_head_external_required=True,
        deep_shared=True,
        reasons=(reason,),
        required_controls=FAIL_CLOSED_REQUIRED_CONTROLS,
    )


def _is_input_governance_migration(path: str) -> bool:
    if not path.startswith(MIGRATION_PREFIX):
        return False
    name = PurePosixPath(path).name.lower()
    return "input_governance" in name or "input-gov" in name or "retire_b2b_auth005_legacy_totp_screen" in name


def _is_p0_exact_head_external_owner(path: str) -> bool:
    return path.startswith(P0_EXACT_HEAD_EXTERNAL_PREFIX) or path in P0_EXACT_HEAD_EXTERNAL_EXACT


def _is_known_shared(path: str, product_known: bool, shared_known: bool, family_known: bool = False) -> bool:
    if product_known or shared_known or family_known:
        return True
    if path.startswith(CI_ROUTER_PREFIX):
        return True
    if path in {MIGRATION_VALIDATOR, MIGRATION_TRANSPORT_TEST, INPUT_GOV_VALIDATOR}:
        return True
    if _is_p0_exact_head_external_owner(path):
        return True
    return path.startswith(KNOWN_SHARED_PREFIXES)


def _registry_for(registry_data: Mapping[str, Any] | None) -> CompiledRegistry:
    return compile_registry(registry_data) if registry_data is not None else load_registry()


def _shared_registry_for(shared_registry_data: Mapping[str, Any] | None) -> CompiledSharedRegistry:
    return compile_shared_registry(shared_registry_data) if shared_registry_data is not None else load_shared_registry()


def classify(
    paths: Iterable[str],
    *,
    registry_data: Mapping[str, Any] | None = None,
    shared_registry_data: Mapping[str, Any] | None = None,
    family_by_path: Mapping[str, str] | None = None,
    family_controls: Mapping[str, Iterable[str]] | None = None,
) -> LaneDecision:
    changed = tuple(sorted({p.strip() for p in paths if p and p.strip()}))
    if not changed:
        return LaneDecision(
            mode="CLASSIFICATION_REQUIRED",
            migration_parity_required=False,
            input_governance_parity_required=False,
            ci_router_selftest_required=False,
            p0_exact_head_external_required=False,
            deep_shared=True,
            reasons=("NO_CHANGED_PATHS",),
            required_controls=(),
        )

    try:
        registry = _registry_for(registry_data)
    except RegistryValidationError as exc:
        return _fail_closed("DEEP_SHARED_REGISTRY_INVALID", f"PRODUCT_REGISTRY_INVALID:{exc.code}")
    try:
        shared_registry = _shared_registry_for(shared_registry_data)
    except SharedRegistryValidationError as exc:
        return _fail_closed("DEEP_SHARED_REGISTRY_INVALID", f"SHARED_REGISTRY_INVALID:{exc.code}")

    migration = False
    input_gov = False
    selftest = False
    p0_external = False
    unknown = False
    deep_shared = False
    product_modes: set[str] = set()
    product_namespaces: set[str] = set()
    required_controls: set[str] = set()
    reasons: list[str] = []
    declared_families = dict(family_by_path or {})
    controls_by_family = {key: tuple(values) for key, values in (family_controls or {}).items()}

    for path in changed:
        try:
            product_lane = registry.match(path)
        except RegistryValidationError as exc:
            return _fail_closed("DEEP_SHARED_REGISTRY_INVALID", f"PRODUCT_REGISTRY_INVALID:{exc.code}")
        shared_control = shared_registry.match(path)

        if path.startswith(MIGRATION_PREFIX):
            migration = True
            required_controls.add(CONTROL_MIGRATION_SOURCE_PARITY)
            reasons.append(f"MIGRATION:{path}")
        if path in {MIGRATION_VALIDATOR, MIGRATION_TRANSPORT_TEST}:
            selftest = True
            required_controls.add(CONTROL_CI_ROUTER_SELFTEST)
            reasons.append(f"MIGRATION_CONTROL_SOURCE_SELFTEST:{path}")
        if _is_input_governance_migration(path) or path == INPUT_GOV_VALIDATOR:
            input_gov = True
            required_controls.add(CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY)
            reasons.append(f"INPUT_GOV:{path}")
        if path.startswith(CI_ROUTER_PREFIX):
            selftest = True
            required_controls.add(CONTROL_CI_ROUTER_SELFTEST)
            reasons.append(f"CI_ROUTER_SELFTEST:{path}")
        if _is_p0_exact_head_external_owner(path):
            p0_external = True
            required_controls.add(CONTROL_P0_EXACT_HEAD_EXTERNAL)
            reasons.append(f"P0_EXACT_HEAD_EXTERNAL:{path}")

        if shared_control is not None:
            migration = migration or shared_control.migration_parity_required
            input_gov = input_gov or shared_control.input_governance_parity_required
            selftest = selftest or shared_control.ci_router_selftest_required
            p0_external = p0_external or shared_control.p0_exact_head_external_required
            deep_shared = deep_shared or shared_control.deep_shared
            required_controls.update(shared_control.required_controls)
            reasons.append(f"SHARED_CONTROL:{shared_control.control_id}:{path}")

        if product_lane is not None:
            migration = migration or product_lane.migration_parity_required
            input_gov = input_gov or product_lane.input_governance_parity_required
            selftest = selftest or product_lane.ci_router_selftest_required
            p0_external = p0_external or product_lane.p0_exact_head_external_required
            deep_shared = deep_shared or product_lane.deep_shared
            required_controls.update(product_lane.required_controls)
            reasons.append(f"PRODUCT_LANE:{product_lane.lane_id}:{path}")
            if product_lane.known:
                product_modes.add(product_lane.mode)
                product_namespaces.add(product_lane.namespace)
            else:
                unknown = True
                reasons.append(f"UNKNOWN_PRODUCT_LANE:{product_lane.lane_id}:{path}")

        declared_family = declared_families.get(path)
        if declared_family is not None:
            family_required = tuple(controls_by_family.get(declared_family, ()))
            required_controls.update(family_required)
            migration = migration or CONTROL_MIGRATION_SOURCE_PARITY in family_required
            input_gov = input_gov or CONTROL_INPUT_GOVERNANCE_MIGRATION_PARITY in family_required
            selftest = selftest or CONTROL_CI_ROUTER_SELFTEST in family_required
            p0_external = p0_external or CONTROL_P0_EXACT_HEAD_EXTERNAL in family_required
            reasons.append(f"CHANGE_FAMILY:{declared_family}:{path}")

        if not _is_known_shared(
            path,
            product_lane is not None and product_lane.known,
            shared_control is not None,
            declared_family is not None,
        ) and not path.startswith(MIGRATION_PREFIX):
            unknown = True
            reasons.append(f"UNKNOWN:{path}")

    if unknown:
        deep_shared = True

    if unknown:
        mode = "CLASSIFICATION_REQUIRED"
    elif migration or input_gov or p0_external:
        mode = "SPECIALIZED_REQUIRED"
    elif selftest:
        mode = "CI_ROUTER_SELFTEST_ONLY"
    elif len(product_modes) == 1 and len(product_namespaces) == 1:
        mode = next(iter(product_modes))
    elif product_modes:
        mode = "S30_MULTI_LANE_KNOWN" if product_namespaces == {"S30"} else "MULTI_PRODUCT_LANE_KNOWN"
    else:
        mode = "DEEP_SHARED_KNOWN"

    required_controls.update(_legacy_required_controls(
        migration_parity_required=migration,
        input_governance_parity_required=input_gov,
        ci_router_selftest_required=selftest,
        p0_exact_head_external_required=p0_external,
    ))
    canonical_required_controls = _canonical_required_controls(required_controls)
    return LaneDecision(
        mode=mode,
        migration_parity_required=migration,
        input_governance_parity_required=input_gov,
        ci_router_selftest_required=selftest,
        p0_exact_head_external_required=p0_external,
        deep_shared=deep_shared,
        reasons=tuple(reasons) or ("KNOWN_SHARED",),
        required_controls=canonical_required_controls,
    )
