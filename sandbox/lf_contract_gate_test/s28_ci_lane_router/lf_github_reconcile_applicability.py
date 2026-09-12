#!/usr/bin/env python3
"""Fail-closed applicability gate for quota-bound LF GitHub reconciliation.

The external reconciler remains REQUIRED by default. The only deterministic
NOT_APPLICABLE case is a change-set composed exclusively of known isolated S30
lane paths from the canonical declarative ownership registry, with no shared or
specialized gate requirements.
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

from s30_lane_ownership import (  # noqa: E402
    RegistryValidationError,
    compile_registry,
    load_registry,
)


@dataclass(frozen=True)
class ReconciliationApplicability:
    required: bool
    state: str
    reason: str
    changed_count: int
    lane_ids: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "required": self.required,
            "state": self.state,
            "reason": self.reason,
            "changed_count": self.changed_count,
            "lane_ids": list(self.lane_ids),
        }


def _required(reason: str, changed_count: int, lane_ids: Iterable[str] = ()) -> ReconciliationApplicability:
    return ReconciliationApplicability(
        required=True,
        state="REQUIRED",
        reason=reason,
        changed_count=changed_count,
        lane_ids=tuple(sorted(set(lane_ids))),
    )


def classify_reconciliation_applicability(
    paths: Iterable[str],
    *,
    registry_data: Mapping[str, Any] | None = None,
) -> ReconciliationApplicability:
    changed = tuple(sorted({path.strip() for path in paths if path and path.strip()}))
    if not changed:
        return _required("NO_CHANGED_PATHS_FAIL_CLOSED", 0)

    try:
        registry = compile_registry(registry_data) if registry_data is not None else load_registry()
    except (RegistryValidationError, OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        code = getattr(exc, "code", type(exc).__name__)
        return _required(f"S30_REGISTRY_INVALID_FAIL_CLOSED:{code}", len(changed))

    lane_ids: list[str] = []
    for path in changed:
        try:
            lane = registry.match(path)
        except RegistryValidationError as exc:
            return _required(
                f"S30_REGISTRY_AMBIGUOUS_FAIL_CLOSED:{exc.code}",
                len(changed),
                lane_ids,
            )

        # Reconciliation is skipped only when every changed path has explicit,
        # known S30 ownership. Non-S30, unknown, mixed and future-unbound paths
        # preserve the historical external reconciliation behavior.
        if lane is None:
            return _required("NON_S30_PATH_REQUIRES_RECONCILIATION", len(changed), lane_ids)
        if not lane.known:
            return _required("UNKNOWN_S30_LANE_REQUIRES_RECONCILIATION", len(changed), [*lane_ids, lane.lane_id])

        lane_ids.append(lane.lane_id)
        if any(
            (
                lane.migration_parity_required,
                lane.input_governance_parity_required,
                lane.p0_exact_head_external_required,
                lane.ci_router_selftest_required,
                lane.deep_shared,
            )
        ):
            return _required(
                "S30_SHARED_OR_SPECIALIZED_GATE_REQUIRES_RECONCILIATION",
                len(changed),
                lane_ids,
            )

    return ReconciliationApplicability(
        required=False,
        state="NOT_APPLICABLE",
        reason="S30_KNOWN_ISOLATED_ONLY",
        changed_count=len(changed),
        lane_ids=tuple(sorted(set(lane_ids))),
    )


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
