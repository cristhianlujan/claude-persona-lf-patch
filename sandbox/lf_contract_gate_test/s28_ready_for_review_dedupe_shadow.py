#!/usr/bin/env python3
"""Strategy 28 C7 shadow classifier for ready_for_review DEEP evidence reuse.

This module is intentionally side-effect free. It does not call GitHub or alter
workflow behavior. It only decides whether an already-completed real DEEP
lf-contract-check is reusable for the exact ready_for_review integration context.
"""
from __future__ import annotations

from datetime import datetime
from time import perf_counter_ns
from typing import Any, Iterable

RUN_DEEP = "RUN_DEEP"
SKIP_READY_REUSE_EXACT_DEEP = "SKIP_READY_REUSE_EXACT_DEEP"
EXPECTED_JOB = "lf-contract-check"
EXPECTED_SOURCE = "authoritative_manifest"


def _sha(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    value = value.strip().lower()
    if len(value) != 40 or any(ch not in "0123456789abcdef" for ch in value):
        return None
    return value


def _completed_at(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _deep_success(record: dict[str, Any]) -> bool:
    return (
        record.get("job_name") == EXPECTED_JOB
        and record.get("job_conclusion") == "success"
        and record.get("real_deep") is True
        and record.get("source_kind") == EXPECTED_SOURCE
    )


def classify_ready_for_review(
    *,
    event_name: str,
    action: str,
    pr_number: int | None,
    head_sha: str,
    event_base_sha: str,
    current_main_sha: str,
    prior_evidence: Iterable[dict[str, Any]],
) -> dict[str, Any]:
    """Return a fail-closed reuse decision for ready_for_review."""
    base_result = {
        "decision": RUN_DEEP,
        "reason": "NOT_READY_FOR_REVIEW",
        "reused_run_id": None,
        "related_count": 0,
        "exact_context_count": 0,
    }
    if event_name != "pull_request" or action != "ready_for_review":
        return base_result

    head = _sha(head_sha)
    event_base = _sha(event_base_sha)
    current_main = _sha(current_main_sha)
    if not isinstance(pr_number, int) or pr_number <= 0 or not head or not event_base or not current_main:
        return {**base_result, "reason": "INVALID_EVENT_CONTEXT_FAIL_DEEP"}

    if current_main != event_base:
        return {**base_result, "reason": "CURRENT_MAIN_DIFFERS_EVENT_BASE_FAIL_DEEP"}

    records = list(prior_evidence)
    related = [
        record
        for record in records
        if isinstance(record, dict)
        and record.get("pr_number") == pr_number
        and _sha(record.get("head_sha")) == head
    ]
    exact = [record for record in related if _sha(record.get("base_sha")) == event_base]
    result = {
        **base_result,
        "related_count": len(related),
        "exact_context_count": len(exact),
    }
    if not exact:
        return {**result, "reason": "NO_EXACT_PRIOR_CONTEXT_FAIL_DEEP"}

    ranked: list[tuple[datetime, int, dict[str, Any]]] = []
    for record in exact:
        completed = _completed_at(record.get("completed_at"))
        run_id = record.get("run_id")
        if completed is None or not isinstance(run_id, int) or run_id <= 0:
            return {**result, "reason": "AMBIGUOUS_OR_INCOMPLETE_EVIDENCE_FAIL_DEEP"}
        ranked.append((completed, run_id, record))

    ranked.sort(key=lambda item: (item[0], item[1]))
    latest = ranked[-1][2]
    if not _deep_success(latest):
        return {**result, "reason": "LATEST_EXACT_CONTEXT_NOT_REAL_DEEP_SUCCESS_FAIL_DEEP"}

    return {
        **result,
        "decision": SKIP_READY_REUSE_EXACT_DEEP,
        "reason": "EXACT_PR_HEAD_BASE_CURRENT_MAIN_AND_REAL_DEEP_SUCCESS",
        "reused_run_id": latest["run_id"],
    }


def _evidence(
    *,
    run_id: int,
    pr_number: int,
    head_sha: str,
    base_sha: str,
    conclusion: str = "success",
    real_deep: bool = True,
    source_kind: str = EXPECTED_SOURCE,
    completed_at: str = "2026-08-27T17:29:39Z",
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "pr_number": pr_number,
        "head_sha": head_sha,
        "base_sha": base_sha,
        "job_name": EXPECTED_JOB,
        "job_conclusion": conclusion,
        "real_deep": real_deep,
        "source_kind": source_kind,
        "completed_at": completed_at,
    }


def self_test() -> dict[str, Any]:
    p257_head = "378d06297b06017ad4a284954fdfddfdb8e7399b"
    p257_base = "93bf5840b974b15499453b4f73d449b7412325ce"
    p540_head = "f46f26dc902aacb9160ece7198604ded086cb01f"
    p540_old_base = "bc9079d9d9f8838ec8a5f8e9d57109d110bd25aa"
    p540_new_base = "eb145283812bf0e504f8b8d42041a706dfa3c6f3"

    positive = _evidence(
        run_id=33098510419,
        pr_number=257,
        head_sha=p257_head,
        base_sha=p257_base,
    )
    p540_prior = _evidence(
        run_id=33982482665,
        pr_number=540,
        head_sha=p540_head,
        base_sha=p540_old_base,
        completed_at="2026-09-05T17:58:09Z",
    )

    cases: list[tuple[str, str, dict[str, Any]]] = [
        ("positive_pr257_exact_context", SKIP_READY_REUSE_EXACT_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[positive])),
        ("negative_pr540_base_changed", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=540, head_sha=p540_head, event_base_sha=p540_new_base, current_main_sha=p540_new_base, prior_evidence=[p540_prior])),
        ("current_main_event_base_mismatch", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p540_new_base, prior_evidence=[positive])),
        ("missing_prior_evidence", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[])),
        ("latest_prior_failed", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[positive, _evidence(run_id=33098510420, pr_number=257, head_sha=p257_head, base_sha=p257_base, conclusion="failure", completed_at="2026-08-27T17:31:00Z")])),
        ("latest_prior_was_skip", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[_evidence(run_id=33098510421, pr_number=257, head_sha=p257_head, base_sha=p257_base, real_deep=False)])),
        ("wrong_pr", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=258, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[positive])),
        ("wrong_head", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha="1" * 40, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[positive])),
        ("wrong_base", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha="2" * 40, current_main_sha="2" * 40, prior_evidence=[positive])),
        ("non_ready_pr_event", RUN_DEEP, dict(event_name="pull_request", action="synchronize", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[positive])),
        ("invalid_sha", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha="not-a-sha", event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[positive])),
        ("latest_success_supersedes_earlier_failure", SKIP_READY_REUSE_EXACT_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[_evidence(run_id=33098510418, pr_number=257, head_sha=p257_head, base_sha=p257_base, conclusion="failure", completed_at="2026-08-27T17:28:00Z"), positive])),
        ("incomplete_exact_evidence", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[{**positive, "completed_at": None}])),
        ("wrong_source_kind", RUN_DEEP, dict(event_name="pull_request", action="ready_for_review", pr_number=257, head_sha=p257_head, event_base_sha=p257_base, current_main_sha=p257_base, prior_evidence=[_evidence(run_id=33098510422, pr_number=257, head_sha=p257_head, base_sha=p257_base, source_kind="workflow_summary_only")])),
    ]

    passed = 0
    for name, expected, kwargs in cases:
        observed = classify_ready_for_review(**kwargs)
        if observed["decision"] != expected:
            raise AssertionError(f"{name}: expected {expected}, observed {observed}")
        passed += 1

    perf_kwargs = cases[0][2]
    loops = 20_000
    started = perf_counter_ns()
    for _ in range(loops):
        classify_ready_for_review(**perf_kwargs)
    elapsed = perf_counter_ns() - started
    ns_per_call = elapsed / loops

    return {
        "result": "PASS",
        "cases": len(cases),
        "passed": passed,
        "false_skip_tolerance": 0,
        "positive_control": "PR257",
        "negative_base_drift_control": "PR540",
        "ns_per_call_shadow": round(ns_per_call, 1),
        "production_authorized": False,
    }


if __name__ == "__main__":
    import json
    print(json.dumps(self_test(), sort_keys=True))
