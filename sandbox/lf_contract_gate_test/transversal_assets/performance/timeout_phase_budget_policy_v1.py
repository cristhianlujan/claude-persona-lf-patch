#!/usr/bin/env python3
"""Phase-aware timeout policy for transverse capabilities.

This module is a pure policy/evaluation helper. It does not mutate role/session
settings and does not increase a timeout by itself. Requests above the declared
budget are blocked unless they carry an exact-source benchmark receipt that is
current for the same phase; even then the result is only an evidence-bound
extension candidate for a higher authority to approve.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any, Awaitable, Mapping, TypeVar

POLICY_SCHEMA = "lf-timeout-phase-budget-policy/v1"
DECISION_SCHEMA = "lf-timeout-phase-budget-decision/v1"
BENCHMARK_SCHEMA = "lf-performance-exact-source-benchmark-receipt/v1"
T = TypeVar("T")


class TimeoutPolicyError(ValueError):
    pass


@dataclass(frozen=True)
class PhaseBudget:
    phase: str
    budget_ms: int


def _validate_policy(policy: Mapping[str, Any]) -> dict[str, int]:
    if not isinstance(policy, Mapping) or policy.get("schema_version") != POLICY_SCHEMA:
        raise TimeoutPolicyError("INVALID_POLICY_SCHEMA")
    raw = policy.get("phase_budgets_ms")
    if not isinstance(raw, Mapping) or not raw:
        raise TimeoutPolicyError("MISSING_PHASE_BUDGETS")
    out: dict[str, int] = {}
    for phase, budget in raw.items():
        if not isinstance(phase, str) or not phase.strip():
            raise TimeoutPolicyError("INVALID_PHASE")
        if isinstance(budget, bool) or not isinstance(budget, int) or budget <= 0:
            raise TimeoutPolicyError(f"INVALID_BUDGET:{phase}")
        out[phase.strip().upper()] = budget
    return out


def _benchmark_is_exact_for(
    receipt: Mapping[str, Any] | None,
    *,
    phase: str,
    exact_source_sha256: str,
    min_samples: int,
) -> tuple[bool, str]:
    if not isinstance(receipt, Mapping):
        return False, "BENCHMARK_RECEIPT_MISSING"
    if receipt.get("schema_version") != BENCHMARK_SCHEMA:
        return False, "BENCHMARK_SCHEMA_MISMATCH"
    if receipt.get("exact_source_sha256") != exact_source_sha256:
        return False, "BENCHMARK_SOURCE_MISMATCH"
    phases = receipt.get("phases")
    if not isinstance(phases, Mapping) or phase not in phases:
        return False, "BENCHMARK_PHASE_MISSING"
    phase_result = phases[phase]
    if not isinstance(phase_result, Mapping):
        return False, "BENCHMARK_PHASE_SHAPE_INVALID"
    sample_count = phase_result.get("sample_count")
    if isinstance(sample_count, bool) or not isinstance(sample_count, int) or sample_count < min_samples:
        return False, "BENCHMARK_SAMPLE_COUNT_INSUFFICIENT"
    for key in ("p50_ms", "p95_ms", "p99_ms"):
        value = phase_result.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
            return False, f"BENCHMARK_PERCENTILE_INVALID:{key}"
    return True, "BENCHMARK_EXACT_SOURCE_VALID"


def evaluate_timeout_request(
    *,
    phase: str,
    requested_timeout_ms: int,
    policy: Mapping[str, Any],
    exact_source_sha256: str,
    benchmark_receipt: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        budgets = _validate_policy(policy)
    except TimeoutPolicyError as exc:
        return {
            "schema_version": DECISION_SCHEMA,
            "decision": "BLOCKED",
            "reason_code": str(exc),
            "mutates_timeout": False,
        }

    if not isinstance(phase, str) or not phase.strip():
        return {"schema_version": DECISION_SCHEMA, "decision": "BLOCKED", "reason_code": "INVALID_PHASE", "mutates_timeout": False}
    normalized_phase = phase.strip().upper()
    if normalized_phase not in budgets:
        return {"schema_version": DECISION_SCHEMA, "decision": "BLOCKED", "reason_code": "UNKNOWN_PHASE", "phase": normalized_phase, "mutates_timeout": False}
    if isinstance(requested_timeout_ms, bool) or not isinstance(requested_timeout_ms, int) or requested_timeout_ms <= 0:
        return {"schema_version": DECISION_SCHEMA, "decision": "BLOCKED", "reason_code": "INVALID_REQUESTED_TIMEOUT", "phase": normalized_phase, "mutates_timeout": False}
    if not isinstance(exact_source_sha256, str) or len(exact_source_sha256) != 64:
        return {"schema_version": DECISION_SCHEMA, "decision": "BLOCKED", "reason_code": "INVALID_EXACT_SOURCE_SHA256", "phase": normalized_phase, "mutates_timeout": False}

    budget_ms = budgets[normalized_phase]
    if requested_timeout_ms <= budget_ms:
        return {
            "schema_version": DECISION_SCHEMA,
            "decision": "ALLOWED_WITHIN_BUDGET",
            "phase": normalized_phase,
            "budget_ms": budget_ms,
            "requested_timeout_ms": requested_timeout_ms,
            "benchmark_required": False,
            "mutates_timeout": False,
        }

    min_samples = int(policy.get("min_benchmark_samples", 3))
    valid, reason = _benchmark_is_exact_for(
        benchmark_receipt,
        phase=normalized_phase,
        exact_source_sha256=exact_source_sha256,
        min_samples=min_samples,
    )
    if not valid:
        return {
            "schema_version": DECISION_SCHEMA,
            "decision": "BLOCKED_BLIND_TIMEOUT_EXTENSION",
            "reason_code": reason,
            "phase": normalized_phase,
            "budget_ms": budget_ms,
            "requested_timeout_ms": requested_timeout_ms,
            "benchmark_required": True,
            "mutates_timeout": False,
        }

    p99_ms = float(benchmark_receipt["phases"][normalized_phase]["p99_ms"])
    if requested_timeout_ms <= p99_ms:
        return {
            "schema_version": DECISION_SCHEMA,
            "decision": "BLOCKED_EXTENSION_NOT_ABOVE_OBSERVED_P99",
            "reason_code": "REQUEST_DOES_NOT_CREATE_MEANINGFUL_HEADROOM",
            "phase": normalized_phase,
            "budget_ms": budget_ms,
            "requested_timeout_ms": requested_timeout_ms,
            "observed_p99_ms": p99_ms,
            "mutates_timeout": False,
        }

    return {
        "schema_version": DECISION_SCHEMA,
        "decision": "EVIDENCE_BOUND_EXTENSION_CANDIDATE",
        "reason_code": "EXACT_SOURCE_BENCHMARK_PRESENT",
        "phase": normalized_phase,
        "budget_ms": budget_ms,
        "requested_timeout_ms": requested_timeout_ms,
        "observed_p99_ms": p99_ms,
        "benchmark_required": True,
        "approval_required": True,
        "mutates_timeout": False,
    }


async def execute_with_phase_budget(
    awaitable: Awaitable[T],
    *,
    phase: str,
    policy: Mapping[str, Any],
) -> T:
    """Execute one already-created awaitable with the configured phase budget.

    This helper exists so the candidate can prove real cancellation semantics in
    a local deterministic negative. It is not a retry loop and does not alter
    the configured budget.
    """
    budgets = _validate_policy(policy)
    normalized_phase = phase.strip().upper() if isinstance(phase, str) else ""
    if normalized_phase not in budgets:
        if hasattr(awaitable, "close"):
            awaitable.close()  # avoid leaking an un-awaited coroutine in tests
        raise TimeoutPolicyError("UNKNOWN_PHASE")
    timeout_s = budgets[normalized_phase] / 1000.0
    return await asyncio.wait_for(awaitable, timeout=timeout_s)
