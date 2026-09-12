#!/usr/bin/env python3
"""Fail-closed applicability gate for quota-bound LF GitHub reconciliation.

Ownership is delegated to the canonical LF CI lane router instead of being
encoded here for one product. Any current or future product that the canonical
router identifies as a known isolated owner can deterministically earn
NOT_APPLICABLE only when every changed path is declaratively owned and no
shared, specialized or external gate is required. Unknown, empty, invalid,
shared and control-surface changes remain REQUIRED.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from lf_ci_lane_router import LaneDecision, classify as classify_ci_lane  # noqa: E402


@dataclass(frozen=True)
class ReconciliationApplicability:
    required: bool
    state: str
    reason: str
    changed_count: int
    lane_ids: tuple[str, ...]
    router_mode: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "required": self.required,
            "state": self.state,
            "reason": self.reason,
            "changed_count": self.changed_count,
            "lane_ids": list(self.lane_ids),
            "router_mode": self.router_mode,
        }


def _ownership_bindings(decision: LaneDecision) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Extract declarative owner IDs and exact owned paths product-agnostically.

    Canonical router ownership reasons use
    `<namespace>_LANE:<owner-id>:<path>`. Reconciliation requires every changed
    path to have one such binding before it can ever return NOT_APPLICABLE.
    """
    owners: set[str] = set()
    paths: set[str] = set()
    for reason in decision.reasons:
        parts = reason.split(":", 2)
        if len(parts) == 3 and parts[0].endswith("_LANE") and parts[1] and parts[2]:
            owners.add(parts[1])
            paths.add(parts[2])
    return tuple(sorted(owners)), tuple(sorted(paths))


def _required(
    reason: str,
    changed_count: int,
    *,
    decision: LaneDecision | None = None,
) -> ReconciliationApplicability:
    owners = _ownership_bindings(decision)[0] if decision is not None else ()
    return ReconciliationApplicability(
        required=True,
        state="REQUIRED",
        reason=reason,
        changed_count=changed_count,
        lane_ids=owners,
        router_mode=decision.mode if decision is not None else "NO_DECISION",
    )


def classify_router_decision(
    paths: Iterable[str],
    decision: LaneDecision,
) -> ReconciliationApplicability:
    """Translate the canonical router decision into external applicability."""
    changed = tuple(sorted({path.strip() for path in paths if path and path.strip()}))
    if not changed:
        return _required("NO_CHANGED_PATHS_FAIL_CLOSED", 0, decision=decision)

    owners, owned_paths = _ownership_bindings(decision)
    # Mixed sets are the critical safety case: an isolated product path cannot
    # mask a sibling shared/unbound path. Every path must be explicitly owned.
    if set(owned_paths) != set(changed):
        return _required("UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION", len(changed), decision=decision)

    if decision.mode.startswith("DEEP_SHARED"):
        return _required("DEEP_SHARED_REQUIRES_RECONCILIATION", len(changed), decision=decision)

    if any(
        (
            decision.migration_parity_required,
            decision.input_governance_parity_required,
            decision.p0_exact_head_external_required,
            decision.ci_router_selftest_required,
            decision.deep_shared,
        )
    ):
        return _required("SHARED_OR_SPECIALIZED_GATE_REQUIRES_RECONCILIATION", len(changed), decision=decision)

    if not owners:
        return _required("NO_DECLARATIVE_OWNER_REQUIRES_RECONCILIATION", len(changed), decision=decision)

    # Preserve the historical S30 reason for workflow/backward compatibility;
    # the decision logic itself is now product-agnostic.
    reason = (
        "S30_KNOWN_ISOLATED_ONLY"
        if all(owner.startswith("S30-") for owner in owners)
        else "KNOWN_ISOLATED_OWNER_ONLY"
    )
    return ReconciliationApplicability(
        required=False,
        state="NOT_APPLICABLE",
        reason=reason,
        changed_count=len(changed),
        lane_ids=owners,
        router_mode=decision.mode,
    )


def classify_reconciliation_applicability(
    paths: Iterable[str],
    *,
    registry_data: Mapping[str, Any] | None = None,
) -> ReconciliationApplicability:
    changed = tuple(sorted({path.strip() for path in paths if path and path.strip()}))
    decision = classify_ci_lane(changed, registry_data=registry_data)
    return classify_router_decision(changed, decision)


def _read_paths(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise SystemExit(f"FAIL_RECONCILIATION_APPLICABILITY_PATHS_READ:{exc}") from exc


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--paths-file", type=Path, required=True)
    args = parser.parse_args()
    result = classify_reconciliation_applicability(_read_paths(args.paths_file))
    print(json.dumps(result.to_dict(), sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
