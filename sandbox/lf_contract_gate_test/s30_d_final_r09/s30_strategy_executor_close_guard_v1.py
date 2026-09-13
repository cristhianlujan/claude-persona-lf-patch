from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any, Mapping, Sequence

FINAL_REPORT_ALLOWED = "FINAL_REPORT_ALLOWED"
CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE = "CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE"
BLOCK_CLOSE_GUARD = "BLOCK_CLOSE_GUARD"

_ALLOWED_STOP_REASONS = {
    "NO_SAFE_WORK_REMAINING",
    "NONDELEGABLE_AUTHORITY_ONLY",
    "EXECUTION_LIMIT_REACHED",
}
_NONE_BATCH = {"", "NONE", "N/A"}


@dataclass(frozen=True)
class CloseGuardDecision:
    can_close: bool
    action: str
    reasons: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _strings(value: Any) -> list[str]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return []
    return [str(x).strip() for x in value if str(x).strip()]


def _blocker_independent_safe_work(blockers: Any) -> list[str]:
    out: list[str] = []
    if not isinstance(blockers, list):
        return out
    for blocker in blockers:
        if not isinstance(blocker, Mapping):
            continue
        out.extend(_strings(blocker.get("independent_safe_work")))
    return out


def evaluate_strategy_close_guard(state: Mapping[str, Any]) -> CloseGuardDecision:
    """
    Executable enforcement extracted from existing S30 semantics.

    Existing policy sources:
      - S30 invariant: BLOCKED_SCOPE_DOES_NOT_HIDE_UNRELATED_SAFE_SCOPE
      - S30 close policy:
        ZERO_EXECUTABLE_SAFE_SCOPES_REMAINING_OR_ALL_TARGETED_SCOPES_TERMINALLY_DISPOSED
      - Existing run close hard-gate fields:
        global_remaining_work_scan, safe_work_remaining_count, next_safe_batch

    This function adds no production/runtime authority and performs no writes.
    """
    reasons: list[str] = []

    if state.get("global_remaining_work_scan") != "PASS":
        reasons.append("GLOBAL_REMAINING_WORK_SCAN_NOT_PASS")

    remaining = state.get("safe_work_remaining_count")
    if not isinstance(remaining, int) or isinstance(remaining, bool) or remaining < 0:
        reasons.append("SAFE_WORK_REMAINING_INVALID")
        remaining_positive = False
    else:
        remaining_positive = remaining > 0

    next_batch = str(state.get("next_safe_batch", "")).strip().upper()
    next_batch_present = next_batch not in _NONE_BATCH

    safe_parallel = _strings(state.get("safe_parallel_work"))
    blocker_safe = _blocker_independent_safe_work(state.get("blockers"))

    safe_work_exists = (
        remaining_positive
        or next_batch_present
        or bool(safe_parallel)
        or bool(blocker_safe)
    )

    if safe_work_exists:
        if remaining_positive:
            reasons.append("SAFE_WORK_REMAINING_NONZERO")
        if next_batch_present:
            reasons.append("NEXT_SAFE_BATCH_PRESENT")
        if safe_parallel:
            reasons.append("SAFE_PARALLEL_WORK_PRESENT")
        if blocker_safe:
            reasons.append("BLOCKER_INDEPENDENT_SAFE_WORK_PRESENT")
        return CloseGuardDecision(
            False,
            CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE,
            tuple(reasons),
        )

    if reasons:
        return CloseGuardDecision(False, BLOCK_CLOSE_GUARD, tuple(reasons))

    stop_reason = str(state.get("why_run_stopped", "")).strip().upper()
    if stop_reason not in _ALLOWED_STOP_REASONS:
        return CloseGuardDecision(
            False,
            BLOCK_CLOSE_GUARD,
            ("STOP_REASON_NOT_ALLOWED",),
        )

    if stop_reason == "EXECUTION_LIMIT_REACHED":
        evidence = str(state.get("execution_limit_evidence", "")).strip()
        if not evidence:
            return CloseGuardDecision(
                False,
                BLOCK_CLOSE_GUARD,
                ("EXECUTION_LIMIT_EVIDENCE_MISSING",),
            )

    return CloseGuardDecision(True, FINAL_REPORT_ALLOWED, ())
