#!/usr/bin/env python3
"""Isolated LangGraph wrapper spike for LF profile runtime.

This module does not replace LF governance. It wraps the existing governed
`execute_profile_runtime` boundary with state, routing, retry, checkpointing,
and optional HITL supplied by LangGraph.
"""
from __future__ import annotations

from typing import Any, Callable, TypedDict

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import RetryPolicy, interrupt

from profile_runtime_runner import (
    RESULT_TYPE,
    RuntimeExecutionBlocked,
    execute_profile_runtime,
)

SPIKE_ID = "LF_LANGGRAPH_SPIKE_001"
LANGGRAPH_PIN = "1.2.11"
TRANSIENT_ADAPTER_DETAILS = frozenset(
    {"ConnectionError", "TimeoutError", "TemporaryProviderError"}
)


class SpikeTransientError(Exception):
    """Retryable wrapper used only by the spike orchestration layer."""


class SpikeState(TypedDict, total=False):
    execution_id: str
    profile_code: str
    profile_slug: str
    profile_sources: list[dict[str, str]]
    input_literal: str
    obligation_manifest: dict[str, Any] | None
    lf_adapter_sources: list[dict[str, Any]] | None
    requires_human: bool
    status: str
    blocking_code: str
    blocking_detail: str
    runtime_result: dict[str, Any]
    post_checks: dict[str, bool]
    orchestration_events: list[str]


def _events(state: SpikeState, event: str) -> list[str]:
    return [*state.get("orchestration_events", []), event]


def _preflight(state: SpikeState) -> SpikeState:
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
        if key not in state
        or state[key] is None
        or (isinstance(state[key], str) and not state[key].strip())
    ]
    if missing:
        return {
            "status": "BLOCKED",
            "blocking_code": "LANGGRAPH_SPIKE_PREFLIGHT_MISSING",
            "blocking_detail": ",".join(missing),
            "orchestration_events": _events(state, "PREFLIGHT_BLOCK"),
        }
    return {
        "status": "PREFLIGHT_PASS",
        "orchestration_events": _events(state, "PREFLIGHT_PASS"),
    }


def _human_gate(state: SpikeState) -> SpikeState:
    if not state.get("requires_human", False):
        return {
            "status": "HITL_NOT_REQUIRED",
            "orchestration_events": _events(state, "HITL_NOT_REQUIRED"),
        }
    approved = interrupt(
        {
            "gate": "LF_HITL",
            "spike_id": SPIKE_ID,
            "execution_id": state["execution_id"],
            "question": "Approve governed profile execution?",
        }
    )
    if approved is not True:
        return {
            "status": "BLOCKED",
            "blocking_code": "LANGGRAPH_SPIKE_HITL_REJECTED",
            "blocking_detail": "Human approval was not true",
            "orchestration_events": _events(state, "HITL_REJECTED"),
        }
    return {
        "status": "HITL_APPROVED",
        "orchestration_events": _events(state, "HITL_APPROVED"),
    }


def _route_after_preflight(state: SpikeState) -> str:
    if state.get("status") == "BLOCKED":
        return "block"
    return "human_gate" if state.get("requires_human", False) else "execute_runtime"


def _route_after_human(state: SpikeState) -> str:
    return "block" if state.get("status") == "BLOCKED" else "execute_runtime"


def _route_after_runtime(state: SpikeState) -> str:
    """Do not let a governed LF runtime block fall through into post-validation."""
    return "block" if state.get("status") == "BLOCKED" else "post_validate"


def _route_after_validation(state: SpikeState) -> str:
    return "block" if state.get("status") == "BLOCKED" else "close"


def build_spike_graph(
    *,
    adapter: Any,
    attestation_verifier: Any,
    checkpointer: Any | None = None,
    runtime_executor: Callable[..., dict[str, Any]] = execute_profile_runtime,
):
    """Build an isolated graph that delegates all LF semantics to the existing runner."""

    def execute_runtime_node(state: SpikeState) -> SpikeState:
        try:
            result = runtime_executor(
                execution_id=state["execution_id"],
                profile_code=state["profile_code"],
                profile_slug=state["profile_slug"],
                profile_sources=state["profile_sources"],
                input_literal=state["input_literal"],
                adapter=adapter,
                attestation_verifier=attestation_verifier,
                allow_test_doubles=True,
                obligation_manifest=state.get("obligation_manifest"),
                lf_adapter_sources=state.get("lf_adapter_sources"),
            )
        except RuntimeExecutionBlocked as exc:
            if (
                exc.code == "RUNTIME_ADAPTER_EXCEPTION"
                and exc.detail in TRANSIENT_ADAPTER_DETAILS
            ):
                raise SpikeTransientError(exc.detail) from exc
            return {
                "status": "BLOCKED",
                "blocking_code": exc.code,
                "blocking_detail": exc.detail or "",
                "orchestration_events": _events(
                    state, f"RUNTIME_BLOCK:{exc.code}"
                ),
            }
        return {
            "status": "RUNTIME_PASS",
            "runtime_result": result,
            "orchestration_events": _events(state, "RUNTIME_PASS"),
        }

    def post_validate(state: SpikeState) -> SpikeState:
        result = state.get("runtime_result")
        checks = {
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
        failed = sorted(key for key, passed in checks.items() if not passed)
        if failed:
            return {
                "status": "BLOCKED",
                "blocking_code": "LANGGRAPH_SPIKE_POST_VALIDATION_FAILED",
                "blocking_detail": ",".join(failed),
                "post_checks": checks,
                "orchestration_events": _events(
                    state, "POST_VALIDATION_BLOCK"
                ),
            }
        return {
            "status": "POST_VALIDATION_PASS",
            "post_checks": checks,
            "orchestration_events": _events(state, "POST_VALIDATION_PASS"),
        }

    def close(state: SpikeState) -> SpikeState:
        return {
            "status": "PASS",
            "orchestration_events": _events(state, "CLOSE_PASS"),
        }

    def block(state: SpikeState) -> SpikeState:
        return {
            "status": "BLOCKED",
            "orchestration_events": _events(state, "CLOSE_BLOCKED"),
        }

    builder = StateGraph(SpikeState)
    builder.add_node("preflight", _preflight)
    builder.add_node("human_gate", _human_gate)
    builder.add_node(
        "execute_runtime",
        execute_runtime_node,
        retry_policy=RetryPolicy(
            max_attempts=3,
            initial_interval=0.01,
            backoff_factor=1.0,
            max_interval=0.01,
            jitter=False,
            retry_on=SpikeTransientError,
        ),
    )
    builder.add_node("post_validate", post_validate)
    builder.add_node("close", close)
    builder.add_node("block", block)

    builder.add_edge(START, "preflight")
    builder.add_conditional_edges(
        "preflight",
        _route_after_preflight,
        {
            "human_gate": "human_gate",
            "execute_runtime": "execute_runtime",
            "block": "block",
        },
    )
    builder.add_conditional_edges(
        "human_gate",
        _route_after_human,
        {"execute_runtime": "execute_runtime", "block": "block"},
    )
    builder.add_conditional_edges(
        "execute_runtime",
        _route_after_runtime,
        {"post_validate": "post_validate", "block": "block"},
    )
    builder.add_conditional_edges(
        "post_validate",
        _route_after_validation,
        {"close": "close", "block": "block"},
    )
    builder.add_edge("close", END)
    builder.add_edge("block", END)

    return builder.compile(checkpointer=checkpointer or InMemorySaver())
