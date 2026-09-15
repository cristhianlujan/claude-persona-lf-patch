#!/usr/bin/env python3
"""Functional API variant for LF_LANGGRAPH_SPIKE_001 R02-B.

This module preserves LF semantic ownership in `execute_profile_runtime` while
using LangGraph's Functional API only for durable orchestration primitives.
"""
from __future__ import annotations

from typing import Any, Callable

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task
from langgraph.types import RetryPolicy, interrupt

from profile_runtime_runner import (
    RESULT_TYPE,
    RuntimeExecutionBlocked,
    execute_profile_runtime,
)
from langgraph_profile_spike import (
    SPIKE_ID,
    SpikeTransientError,
    TRANSIENT_ADAPTER_DETAILS,
)


def _preflight(payload: dict[str, Any]) -> tuple[bool, str]:
    required = (
        "execution_id",
        "profile_code",
        "profile_slug",
        "profile_sources",
        "input_literal",
    )
    missing = [
        key
        for key in required
        if key not in payload
        or payload[key] is None
        or (isinstance(payload[key], str) and not payload[key].strip())
    ]
    return (not missing, ",".join(missing))


def _post_checks(result: Any) -> dict[str, bool]:
    return {
        "result_is_object": isinstance(result, dict),
        "result_type_preserved": isinstance(result, dict)
        and result.get("result_type") == RESULT_TYPE,
        "request_preserved": isinstance(result, dict)
        and isinstance(result.get("request"), dict),
        "raw_output_preserved": isinstance(result, dict)
        and result.get("raw_output") not in (None, "", {}, []),
        "attestation_verified": isinstance(result, dict)
        and isinstance(result.get("runtime_attestation_verification"), dict)
        and result["runtime_attestation_verification"].get("verified") is True,
        "receipt_preserved": isinstance(result, dict)
        and isinstance(result.get("receipt"), dict)
        and bool(result["receipt"].get("receipt_sha256")),
    }


def build_functional_workflow(
    *,
    adapter: Any,
    attestation_verifier: Any,
    checkpointer: Any | None = None,
    runtime_executor: Callable[..., dict[str, Any]] = execute_profile_runtime,
):
    """Build the same LF contract using @entrypoint/@task and native control flow."""

    @task(
        name="lf_execute_profile_runtime",
        retry_policy=RetryPolicy(
            max_attempts=3,
            initial_interval=0.01,
            backoff_factor=1.0,
            max_interval=0.01,
            jitter=False,
            retry_on=SpikeTransientError,
        ),
    )
    def execute_runtime_task(payload: dict[str, Any]) -> dict[str, Any]:
        try:
            result = runtime_executor(
                execution_id=payload["execution_id"],
                profile_code=payload["profile_code"],
                profile_slug=payload["profile_slug"],
                profile_sources=payload["profile_sources"],
                input_literal=payload["input_literal"],
                adapter=adapter,
                attestation_verifier=attestation_verifier,
                allow_test_doubles=True,
                obligation_manifest=payload.get("obligation_manifest"),
                lf_adapter_sources=payload.get("lf_adapter_sources"),
            )
        except RuntimeExecutionBlocked as exc:
            if (
                exc.code == "RUNTIME_ADAPTER_EXCEPTION"
                and exc.detail in TRANSIENT_ADAPTER_DETAILS
            ):
                raise SpikeTransientError(exc.detail) from exc
            return {
                "kind": "BLOCKED",
                "blocking_code": exc.code,
                "blocking_detail": exc.detail or "",
            }
        return {"kind": "PASS", "runtime_result": result}

    @entrypoint(checkpointer=checkpointer or InMemorySaver())
    def workflow(payload: dict[str, Any]) -> dict[str, Any]:
        events: list[str] = []

        preflight_ok, missing = _preflight(payload)
        if not preflight_ok:
            return {
                "status": "BLOCKED",
                "blocking_code": "LANGGRAPH_SPIKE_PREFLIGHT_MISSING",
                "blocking_detail": missing,
                "orchestration_events": ["PREFLIGHT_BLOCK", "CLOSE_BLOCKED"],
            }
        events.append("PREFLIGHT_PASS")

        if payload.get("requires_human", False):
            approved = interrupt(
                {
                    "gate": "LF_HITL",
                    "spike_id": SPIKE_ID,
                    "execution_id": payload["execution_id"],
                    "question": "Approve governed profile execution?",
                }
            )
            if approved is not True:
                return {
                    "status": "BLOCKED",
                    "blocking_code": "LANGGRAPH_SPIKE_HITL_REJECTED",
                    "blocking_detail": "Human approval was not true",
                    "orchestration_events": [
                        *events,
                        "HITL_REJECTED",
                        "CLOSE_BLOCKED",
                    ],
                }
            events.append("HITL_APPROVED")

        runtime = execute_runtime_task(payload).result()
        if runtime["kind"] == "BLOCKED":
            return {
                "status": "BLOCKED",
                "blocking_code": runtime["blocking_code"],
                "blocking_detail": runtime["blocking_detail"],
                "orchestration_events": [
                    *events,
                    f"RUNTIME_BLOCK:{runtime['blocking_code']}",
                    "CLOSE_BLOCKED",
                ],
            }

        events.append("RUNTIME_PASS")
        result = runtime["runtime_result"]
        checks = _post_checks(result)
        failed = sorted(key for key, passed in checks.items() if not passed)
        if failed:
            return {
                "status": "BLOCKED",
                "blocking_code": "LANGGRAPH_SPIKE_POST_VALIDATION_FAILED",
                "blocking_detail": ",".join(failed),
                "runtime_result": result,
                "post_checks": checks,
                "orchestration_events": [
                    *events,
                    "POST_VALIDATION_BLOCK",
                    "CLOSE_BLOCKED",
                ],
            }

        return {
            "status": "PASS",
            "runtime_result": result,
            "post_checks": checks,
            "orchestration_events": [
                *events,
                "POST_VALIDATION_PASS",
                "CLOSE_PASS",
            ],
        }

    return workflow
