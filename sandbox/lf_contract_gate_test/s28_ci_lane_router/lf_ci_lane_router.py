#!/usr/bin/env python3
"""Fail-closed applicability router for specialized lf-contract-check lanes.

S30 ownership is declarative. The router consumes a versioned registry and keeps
unknown or invalid ownership fail-closed instead of granting specialized N/A.
"""
from __future__ import annotations

from pathlib import PurePosixPath
from typing import Iterable, Mapping, Any

from s30_lane_ownership import (
    CompiledRegistry,
    RegistryValidationError,
    compile_registry,
    load_registry,
)

MIGRATION_PREFIX = "supabase/migrations/"
MIGRATION_VALIDATOR = "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
INPUT_GOV_VALIDATOR = "sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py"
CI_WORKFLOW = ".github/workflows/lf-contract-check.yml"
VALIDATE_LF_PACKS_WORKFLOW = ".github/workflows/validate-lf-packs.yml"
CI_ROUTER_PREFIX = "sandbox/lf_contract_gate_test/s28_ci_lane_router/"
P0_RUNTIME_ENTRYPOINT = "sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT.py"
P0_EXACT_HEAD_EXTERNAL_PREFIX = "supabase/functions/lf-p0-exact-head-evidence-broker-v2/"
P0_EXACT_HEAD_EXTERNAL_EXACT = frozenset({
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v1.py",
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_ci_v2.py",
    "sandbox/lf_contract_gate_test/p0_exact_head_real_source_v2.json",
    "supabase/config.toml",
})

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
    ) -> None:
        self.mode = mode
        self.migration_parity_required = migration_parity_required
        self.input_governance_parity_required = input_governance_parity_required
        self.ci_router_selftest_required = ci_router_selftest_required
        self.p0_exact_head_external_required = p0_exact_head_external_required
        self.deep_shared = deep_shared
        self.reasons = reasons

    def __repr__(self) -> str:
        return (
            "LaneDecision("
            f"mode={self.mode!r}, migration_parity_required={self.migration_parity_required!r}, "
            f"input_governance_parity_required={self.input_governance_parity_required!r}, "
            f"ci_router_selftest_required={self.ci_router_selftest_required!r}, "
            f"p0_exact_head_external_required={self.p0_exact_head_external_required!r}, "
            f"deep_shared={self.deep_shared!r}, reasons={self.reasons!r})"
        )

    def to_dict(self) -> dict:
        return {
            "mode": self.mode,
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
    )


def _is_input_governance_migration(path: str) -> bool:
    if not path.startswith(MIGRATION_PREFIX):
        return False
    name = PurePosixPath(path).name.lower()
    return "input_governance" in name or "input-gov" in name or "retire_b2b_auth005_legacy_totp_screen" in name


def _is_p0_exact_head_external_owner(path: str) -> bool:
    return path.startswith(P0_EXACT_HEAD_EXTERNAL_PREFIX) or path in P0_EXACT_HEAD_EXTERNAL_EXACT


def _is_known_shared(path: str, s30_known: bool) -> bool:
    if s30_known:
        return True
    if path in {CI_WORKFLOW, VALIDATE_LF_PACKS_WORKFLOW, P0_RUNTIME_ENTRYPOINT}:
        return True
    if path.startswith(CI_ROUTER_PREFIX):
        return True
    if path in {MIGRATION_VALIDATOR, INPUT_GOV_VALIDATOR}:
        return True
    if _is_p0_exact_head_external_owner(path):
        return True
    return path.startswith(KNOWN_SHARED_PREFIXES)


def _registry_for(registry_data: Mapping[str, Any] | None) -> CompiledRegistry:
    return compile_registry(registry_data) if registry_data is not None else load_registry()


def classify(paths: Iterable[str], *, registry_data: Mapping[str, Any] | None = None) -> LaneDecision:
    changed = tuple(sorted({p.strip() for p in paths if p and p.strip()}))
    if not changed:
        return _fail_closed("DEEP_SHARED_EMPTY_FAIL_CLOSED", "NO_CHANGED_PATHS")

    try:
        registry = _registry_for(registry_data)
    except RegistryValidationError as exc:
        return _fail_closed("DEEP_SHARED_REGISTRY_INVALID", f"S30_REGISTRY_INVALID:{exc.code}")

    migration = False
    input_gov = False
    selftest = False
    p0_external = False
    unknown = False
    deep_shared = False
    s30_modes: set[str] = set()
    reasons: list[str] = []

    for path in changed:
        try:
            s30_lane = registry.match(path)
        except RegistryValidationError as exc:
            return _fail_closed("DEEP_SHARED_REGISTRY_INVALID", f"S30_REGISTRY_INVALID:{exc.code}")

        if path.startswith(MIGRATION_PREFIX) or path == MIGRATION_VALIDATOR:
            migration = True
            reasons.append(f"MIGRATION:{path}")
        if _is_input_governance_migration(path) or path == INPUT_GOV_VALIDATOR:
            input_gov = True
            reasons.append(f"INPUT_GOV:{path}")
        if path in {CI_WORKFLOW, VALIDATE_LF_PACKS_WORKFLOW, P0_RUNTIME_ENTRYPOINT} or path.startswith(CI_ROUTER_PREFIX):
            selftest = True
            reasons.append(f"CI_ROUTER_SELFTEST:{path}")
        if _is_p0_exact_head_external_owner(path):
            p0_external = True
            reasons.append(f"P0_EXACT_HEAD_EXTERNAL:{path}")

        if s30_lane is not None:
            migration = migration or s30_lane.migration_parity_required
            input_gov = input_gov or s30_lane.input_governance_parity_required
            selftest = selftest or s30_lane.ci_router_selftest_required
            p0_external = p0_external or s30_lane.p0_exact_head_external_required
            deep_shared = deep_shared or s30_lane.deep_shared
            reasons.append(f"S30_LANE:{s30_lane.lane_id}:{path}")
            if s30_lane.known:
                s30_modes.add(s30_lane.mode)
            else:
                unknown = True
                reasons.append(f"UNKNOWN_S30_LANE:{s30_lane.lane_id}:{path}")

        if not _is_known_shared(path, s30_lane is not None and s30_lane.known) and not path.startswith(MIGRATION_PREFIX):
            unknown = True
            reasons.append(f"UNKNOWN:{path}")

    if unknown:
        # Unknown ownership never earns a specialized N/A. Preserve the current
        # defensive parity/external gates and mark the decision deep-shared.
        migration = True
        input_gov = True
        p0_external = True
        deep_shared = True

    if unknown:
        mode = "DEEP_SHARED_UNKNOWN"
    elif migration or input_gov or p0_external:
        mode = "SPECIALIZED_REQUIRED"
    elif selftest:
        mode = "CI_ROUTER_SELFTEST_ONLY"
    elif len(s30_modes) == 1:
        mode = next(iter(s30_modes))
    elif len(s30_modes) > 1:
        mode = "S30_MULTI_LANE_KNOWN"
    else:
        mode = "DEEP_SHARED_KNOWN"

    return LaneDecision(
        mode=mode,
        migration_parity_required=migration,
        input_governance_parity_required=input_gov,
        ci_router_selftest_required=selftest,
        p0_exact_head_external_required=p0_external,
        deep_shared=deep_shared,
        reasons=tuple(reasons) or ("KNOWN_SHARED",),
    )
