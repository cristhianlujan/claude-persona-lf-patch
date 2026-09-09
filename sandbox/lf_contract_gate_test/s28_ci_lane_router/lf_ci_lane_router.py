#!/usr/bin/env python3
"""Fail-closed applicability router for specialized lf-contract-check lanes.

This module does not decide whether the shared DEEP contract check runs. It only
classifies whether specialized migration parity checks, CI-router self-tests,
and the live P0 exact-head external broker probe apply to the changed-file set.
"""

from __future__ import annotations

from pathlib import PurePosixPath
from typing import Iterable

S30_POLICY_PREFIX = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/"
S30_SELF_GOVERNANCE_PREFIX = "sandbox/lf_contract_gate_test/s30_self_governance/"
S30_SELF_GOVERNANCE_RECEIPT_PREFIX = "sandbox/lf_contract_gate_test/receipts/s30_a_self_governance_gate_"
OP24_LINEAGE_SOURCE_PREFIX = "sandbox/lf_contract_gate_test/op24_lineage_durable_candidate/"
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


def _is_input_governance_migration(path: str) -> bool:
    if not path.startswith(MIGRATION_PREFIX):
        return False
    name = PurePosixPath(path).name.lower()
    return "input_governance" in name or "input-gov" in name or "retire_b2b_auth005_legacy_totp_screen" in name


def _is_p0_exact_head_external_owner(path: str) -> bool:
    return path.startswith(P0_EXACT_HEAD_EXTERNAL_PREFIX) or path in P0_EXACT_HEAD_EXTERNAL_EXACT


def _is_s30_policy(path: str) -> bool:
    return path.startswith(S30_POLICY_PREFIX)


def _is_s30_self_governance(path: str) -> bool:
    return path.startswith(S30_SELF_GOVERNANCE_PREFIX) or path.startswith(S30_SELF_GOVERNANCE_RECEIPT_PREFIX)


def _is_s30_isolated(path: str) -> bool:
    return _is_s30_policy(path) or _is_s30_self_governance(path)


def _is_known_shared(path: str) -> bool:
    if path in {CI_WORKFLOW, VALIDATE_LF_PACKS_WORKFLOW, P0_RUNTIME_ENTRYPOINT}:
        return True
    if path.startswith(CI_ROUTER_PREFIX) or _is_s30_isolated(path) or path.startswith(OP24_LINEAGE_SOURCE_PREFIX):
        return True
    if path in {MIGRATION_VALIDATOR, INPUT_GOV_VALIDATOR}:
        return True
    if _is_p0_exact_head_external_owner(path):
        return True
    return path.startswith(KNOWN_SHARED_PREFIXES)


def classify(paths: Iterable[str]) -> LaneDecision:
    changed = tuple(sorted({p.strip() for p in paths if p and p.strip()}))
    if not changed:
        return LaneDecision(
            mode="DEEP_SHARED_EMPTY_FAIL_CLOSED",
            migration_parity_required=True,
            input_governance_parity_required=True,
            ci_router_selftest_required=True,
            p0_exact_head_external_required=True,
            deep_shared=True,
            reasons=("NO_CHANGED_PATHS",),
        )

    migration = False
    input_gov = False
    selftest = False
    p0_external = False
    unknown = False
    s30_policy = False
    s30_self_governance = False
    reasons: list[str] = []

    for path in changed:
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
        if _is_s30_policy(path):
            s30_policy = True
            reasons.append(f"S30_POLICY:{path}")
        if _is_s30_self_governance(path):
            s30_self_governance = True
            reasons.append(f"S30_SELF_GOVERNANCE:{path}")
        if not _is_known_shared(path) and not path.startswith(MIGRATION_PREFIX):
            unknown = True
            reasons.append(f"UNKNOWN:{path}")

    if unknown:
        # Unknown ownership never earns a specialized N/A. Run all external/
        # parity obligations rather than risking a false skip.
        migration = True
        input_gov = True
        p0_external = True

    if unknown:
        mode = "DEEP_SHARED_UNKNOWN"
    elif migration or input_gov or p0_external:
        mode = "SPECIALIZED_REQUIRED"
    elif selftest:
        mode = "CI_ROUTER_SELFTEST_ONLY"
    elif s30_self_governance:
        mode = "S30_SELF_GOVERNANCE_ISOLATED"
    elif s30_policy:
        mode = "S30_POLICY_ISOLATED"
    else:
        mode = "DEEP_SHARED_KNOWN"

    return LaneDecision(
        mode=mode,
        migration_parity_required=migration,
        input_governance_parity_required=input_gov,
        ci_router_selftest_required=selftest,
        p0_exact_head_external_required=p0_external,
        deep_shared=unknown,
        reasons=tuple(reasons) or ("KNOWN_SHARED",),
    )
