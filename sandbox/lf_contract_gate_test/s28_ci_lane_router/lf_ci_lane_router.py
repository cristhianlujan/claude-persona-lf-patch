#!/usr/bin/env python3
"""Fail-closed applicability router for specialized lf-contract-check lanes.

This module does not decide whether the shared DEEP contract check runs. It only
classifies whether specialized migration parity checks and CI-router self-tests
apply to the current changed-file set.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import PurePosixPath
from typing import Iterable

S30_PREFIX = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/"
MIGRATION_PREFIX = "supabase/migrations/"
MIGRATION_VALIDATOR = "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
INPUT_GOV_VALIDATOR = "sandbox/lf_contract_gate_test/input_governance_migration_parity_compact.py"
CI_WORKFLOW = ".github/workflows/lf-contract-check.yml"
CI_ROUTER_PREFIX = "sandbox/lf_contract_gate_test/s28_ci_lane_router/"

KNOWN_SHARED_PREFIXES = (
    "sandbox/lf_contract_gate_test/",
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


@dataclass(frozen=True)
class LaneDecision:
    mode: str
    migration_parity_required: bool
    input_governance_parity_required: bool
    ci_router_selftest_required: bool
    deep_shared: bool
    reasons: tuple[str, ...]

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["reasons"] = list(self.reasons)
        return payload


def _is_input_governance_migration(path: str) -> bool:
    if not path.startswith(MIGRATION_PREFIX):
        return False
    name = PurePosixPath(path).name.lower()
    return "input_governance" in name or "input-gov" in name or "retire_b2b_auth005_legacy_totp_screen" in name


def _is_known_shared(path: str) -> bool:
    if path == CI_WORKFLOW:
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
            deep_shared=True,
            reasons=("NO_CHANGED_PATHS",),
        )

    migration = False
    input_gov = False
    selftest = False
    unknown = False
    s30 = False
    reasons: list[str] = []

    for path in changed:
        if path.startswith(MIGRATION_PREFIX) or path == MIGRATION_VALIDATOR:
            migration = True
            reasons.append(f"MIGRATION:{path}")
        if _is_input_governance_migration(path) or path == INPUT_GOV_VALIDATOR:
            input_gov = True
            reasons.append(f"INPUT_GOV:{path}")
        if path == CI_WORKFLOW or path.startswith(CI_ROUTER_PREFIX):
            selftest = True
            reasons.append(f"CI_ROUTER_SELFTEST:{path}")
        if path.startswith(S30_PREFIX):
            s30 = True
            reasons.append(f"S30_POLICY:{path}")
        if not _is_known_shared(path) and not path.startswith(MIGRATION_PREFIX):
            unknown = True
            reasons.append(f"UNKNOWN:{path}")

    if unknown:
        # Unknown ownership never earns a specialized N/A. Run the expensive
        # parity lanes rather than risking a false skip.
        migration = True
        input_gov = True

    if unknown:
        mode = "DEEP_SHARED_UNKNOWN"
    elif migration or input_gov:
        mode = "SPECIALIZED_REQUIRED"
    elif selftest:
        mode = "CI_ROUTER_SELFTEST_ONLY"
    elif s30:
        mode = "S30_POLICY_ISOLATED"
    else:
        mode = "DEEP_SHARED_KNOWN"

    return LaneDecision(
        mode=mode,
        migration_parity_required=migration,
        input_governance_parity_required=input_gov,
        ci_router_selftest_required=selftest,
        deep_shared=unknown,
        reasons=tuple(reasons) or ("KNOWN_SHARED",),
    )
