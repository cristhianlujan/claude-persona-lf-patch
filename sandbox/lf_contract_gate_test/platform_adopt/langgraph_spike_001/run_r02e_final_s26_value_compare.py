#!/usr/bin/env python3
from __future__ import annotations

import inspect
import json
import os
import statistics
import sys
import time
from pathlib import Path
from typing import Any

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task
from langgraph.types import Command, RetryPolicy, interrupt

S26_CANDIDATE_SHA = "485f5c77ac568a056647f57b5f04be7698816902"
LANGGRAPH_PIN = "1.2.11"
BENCHMARK_WARMUPS = 10
BENCHMARK_RUNS = 100
SYNTHETIC_OVERHEAD_BUDGET_MS = 5.0

CANDIDATE_ROOT = Path(os.environ.get("S26_CANDIDATE_ROOT", "s26_candidate")).resolve()
RUNTIME_DIR = CANDIDATE_ROOT / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
if not RUNTIME_DIR.exists():
    raise RuntimeError(f"R02E_CANDIDATE_RUNTIME_NOT_FOUND:{RUNTIME_DIR}")
sys.path.insert(0, str(RUNTIME_DIR))

from profile_runtime_runner import (  # noqa: E402
    RESPONSE_TYPE,
    RuntimeExecutionBlocked,
    execute_profile_runtime,
)
from validate_profile_execution import canonical_json_sha256  # noqa: E402


class TemporaryProviderError(RuntimeError):
    pass


class TransientRetrySignal(RuntimeError):
    pass


class DeterministicAdapter:
    adapter_id = "r02e-deterministic-adapter"
    is_test_double = True

    def __init__(self, failures_before_success: int = 0, failure_type: type[Exception] | None = None) -> None:
        self.failures_before_success = failures_before_success
        self.failure_type = failure_type
        self.calls = 0

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        self.calls += 1
        if self.calls <= self.failures_before_success:
            failure_type = self.failure_type or RuntimeError
            raise failure_type("r02e-controlled-failure")
        attestation = {
            "provider": "R02E_DETERMINISTIC",
            "model_id": "fixture-no-network",
            "run_id": f"r02e-{request['request_sha256'][:16]}",
            "attested_at": "2026-09-12T17:35:00+00:00",
            "adapter_id": self.adapter_id,
            "request_sha256": request["request_sha256"],
            "profile_source_sha256": request["profile_source_sha256"],
            "input_sha256": request["input_sha256"],
            "operation_code": request["operation_code"],
            "profile_code": request["profile_code"],
            "profile_slug": request["profile_slug"],
        }
        return {
            "response_type": RESPONSE_TYPE,
            "raw_output": {
                "schema": "R02E_FINAL_S26_FIXTURE_V1",
                "decision": "PASS",
                "layout": "STANDARD_GRID_STACK",
            },
            "runtime_attestation": attestation,
        }


class DeterministicVerifier:
    verifier_id = "r02e-deterministic-verifier"
    is_test_double = True

    def verify(self, *, request: dict[str, Any], response: dict[str, Any], adapter: Any) -> dict[str, Any]:
        response_sha = canonical_json_sha256(response)
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": canonical_json_sha256(
                {
                    "candidate_sha": S26_CANDIDATE_SHA,
                    "request_sha256": request["request_sha256"],
                    "response_sha256": response_sha,
                    "adapter_id": adapter.adapter_id,
                }
            ),
        }


def payload(*, requires_human: bool = False) -> dict[str, Any]:
    return {
        "execution_id": "EXEC-R02E-S26-FINAL-001",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "profile_slug": "ui_architect",
        "profile_sources": [
            {
                "ref": "profiles/ui_architect/SKILL.md",
                "content": "R02-E final S26 deterministic comparison fixture; source content is bounded and non-authoritative.",
            }
        ],
        "input_literal": "R02-E compare final S26 direct runtime against LangGraph Functional without changing LF semantics.",
        "requires_human": requires_human,
    }


def _runtime_kwargs(data: dict[str, Any]) -> dict[str, Any]:
    return {
        "execution_id": data["execution_id"],
        "profile_code": data["profile_code"],
        "profile_slug": data["profile_slug"],
        "profile_sources": data["profile_sources"],
        "input_literal": data["input_literal"],
        "obligation_manifest": data.get("obligation_manifest"),
        "lf_adapter_sources": data.get("lf_adapter_sources"),
    }


def run_direct(data: dict[str, Any], adapter: Any, verifier: Any) -> dict[str, Any]:
    try:
        result = execute_profile_runtime(
            **_runtime_kwargs(data),
            adapter=adapter,
            attestation_verifier=verifier,
            allow_test_doubles=True,
        )
    except RuntimeExecutionBlocked as exc:
        return {
            "status": "BLOCKED",
            "blocking_code": exc.code,
            "blocking_detail": exc.detail or "",
        }
    return {"status": "PASS", "runtime_result": result}


def build_functional_workflow(*, adapter: Any, verifier: Any, checkpointer: Any):
    @task(
        name="lf_r02e_execute_final_s26_runtime",
        retry_policy=RetryPolicy(
            max_attempts=3,
            initial_interval=0.001,
            backoff_factor=1.0,
            max_interval=0.001,
            jitter=False,
            retry_on=TransientRetrySignal,
        ),
    )
    def execute_task(data: dict[str, Any]) -> dict[str, Any]:
        try:
            result = execute_profile_runtime(
                **_runtime_kwargs(data),
                adapter=adapter,
                attestation_verifier=verifier,
                allow_test_doubles=True,
            )
        except RuntimeExecutionBlocked as exc:
            if exc.code == "RUNTIME_ADAPTER_EXCEPTION" and exc.detail == "TemporaryProviderError":
                raise TransientRetrySignal(exc.detail) from exc
            return {
                "status": "BLOCKED",
                "blocking_code": exc.code,
                "blocking_detail": exc.detail or "",
            }
        return {"status": "PASS", "runtime_result": result}

    @entrypoint(checkpointer=checkpointer)
    def workflow(data: dict[str, Any]) -> dict[str, Any]:
        if data.get("requires_human", False):
            approved = interrupt(
                {
                    "gate": "LF_HITL",
                    "execution_id": data["execution_id"],
                    "candidate_sha": S26_CANDIDATE_SHA,
                    "question": "Approve bounded final-S26 execution?",
                }
            )
            if approved is not True:
                return {
                    "status": "BLOCKED",
                    "blocking_code": "R02E_HITL_REJECTED",
                    "blocking_detail": "Human approval was not true",
                }
        return execute_task(data).result()

    return workflow


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    idx = max(0, min(len(ordered) - 1, int(round((len(ordered) - 1) * p))))
    return ordered[idx]


def nonblank_noncomment_loc(source: str) -> int:
    return sum(1 for line in source.splitlines() if line.strip() and not line.lstrip().startswith("#"))


def main() -> int:
    base_payload = payload()

    # 1. Exact semantic/result parity on the final S26 candidate.
    direct_adapter = DeterministicAdapter()
    direct_verifier = DeterministicVerifier()
    direct = run_direct(base_payload, direct_adapter, direct_verifier)

    functional_adapter = DeterministicAdapter()
    functional_verifier = DeterministicVerifier()
    parity_saver = InMemorySaver()
    functional = build_functional_workflow(
        adapter=functional_adapter,
        verifier=functional_verifier,
        checkpointer=parity_saver,
    )
    functional_config = {"configurable": {"thread_id": "r02e-final-parity"}}
    wrapped = functional.invoke(base_payload, config=functional_config)

    exact_result_parity = (
        direct.get("status") == "PASS"
        and wrapped.get("status") == "PASS"
        and direct.get("runtime_result") == wrapped.get("runtime_result")
    )
    if not exact_result_parity:
        raise AssertionError("R02E_FINAL_S26_RESULT_PARITY_FAILED")

    direct_result_sha = canonical_json_sha256(direct["runtime_result"])
    functional_result_sha = canonical_json_sha256(wrapped["runtime_result"])

    # 2. Non-transient fail-closed parity.
    direct_block_adapter = DeterministicAdapter(failures_before_success=3, failure_type=ValueError)
    direct_block = run_direct(base_payload, direct_block_adapter, DeterministicVerifier())
    functional_block_adapter = DeterministicAdapter(failures_before_success=3, failure_type=ValueError)
    functional_block = build_functional_workflow(
        adapter=functional_block_adapter,
        verifier=DeterministicVerifier(),
        checkpointer=InMemorySaver(),
    ).invoke(base_payload, config={"configurable": {"thread_id": "r02e-final-block"}})
    fail_closed_parity = direct_block == functional_block
    if not fail_closed_parity:
        raise AssertionError("R02E_FAIL_CLOSED_PARITY_FAILED")

    # 3. Tangible retry comparison: direct runner blocks on first transient fault;
    # LangGraph retries only the explicitly classified transient fault and succeeds.
    direct_transient_adapter = DeterministicAdapter(
        failures_before_success=1,
        failure_type=TemporaryProviderError,
    )
    direct_transient = run_direct(base_payload, direct_transient_adapter, DeterministicVerifier())

    functional_transient_adapter = DeterministicAdapter(
        failures_before_success=1,
        failure_type=TemporaryProviderError,
    )
    transient_workflow = build_functional_workflow(
        adapter=functional_transient_adapter,
        verifier=DeterministicVerifier(),
        checkpointer=InMemorySaver(),
    )
    functional_transient = transient_workflow.invoke(
        base_payload,
        config={"configurable": {"thread_id": "r02e-final-transient"}},
    )
    transient_recovery_gain = (
        direct_transient.get("status") == "BLOCKED"
        and direct_transient.get("blocking_code") == "RUNTIME_ADAPTER_EXCEPTION"
        and direct_transient_adapter.calls == 1
        and functional_transient.get("status") == "PASS"
        and functional_transient_adapter.calls == 2
    )
    if not transient_recovery_gain:
        raise AssertionError("R02E_TRANSIENT_RECOVERY_GAIN_NOT_PROVEN")

    # 4. HITL pause/resume and reject without executing LF before approval.
    approve_adapter = DeterministicAdapter()
    approve_workflow = build_functional_workflow(
        adapter=approve_adapter,
        verifier=DeterministicVerifier(),
        checkpointer=InMemorySaver(),
    )
    approve_config = {"configurable": {"thread_id": "r02e-final-hitl-approve"}}
    initial = approve_workflow.invoke(payload(requires_human=True), config=approve_config)
    hitl_paused_before_execution = "__interrupt__" in initial and approve_adapter.calls == 0
    resumed = approve_workflow.invoke(Command(resume=True), config=approve_config)
    hitl_resume_pass = resumed.get("status") == "PASS" and approve_adapter.calls == 1

    reject_adapter = DeterministicAdapter()
    reject_workflow = build_functional_workflow(
        adapter=reject_adapter,
        verifier=DeterministicVerifier(),
        checkpointer=InMemorySaver(),
    )
    reject_config = {"configurable": {"thread_id": "r02e-final-hitl-reject"}}
    reject_workflow.invoke(payload(requires_human=True), config=reject_config)
    rejected = reject_workflow.invoke(Command(resume=False), config=reject_config)
    hitl_reject_fail_closed = (
        rejected.get("status") == "BLOCKED"
        and rejected.get("blocking_code") == "R02E_HITL_REJECTED"
        and reject_adapter.calls == 0
    )
    if not (hitl_paused_before_execution and hitl_resume_pass and hitl_reject_fail_closed):
        raise AssertionError("R02E_HITL_COMPARISON_FAILED")

    checkpoint_history_count = len(list(functional.get_state_history(functional_config)))
    if checkpoint_history_count < 1:
        raise AssertionError("R02E_CHECKPOINT_HISTORY_MISSING")

    # 5. Synthetic orchestration overhead: same candidate LF runtime, no model/network.
    bench_direct_adapter = DeterministicAdapter()
    bench_direct_verifier = DeterministicVerifier()
    for _ in range(BENCHMARK_WARMUPS):
        run_direct(base_payload, bench_direct_adapter, bench_direct_verifier)
    direct_samples: list[float] = []
    for _ in range(BENCHMARK_RUNS):
        t0 = time.perf_counter_ns()
        result = run_direct(base_payload, bench_direct_adapter, bench_direct_verifier)
        if result.get("status") != "PASS":
            raise AssertionError("R02E_DIRECT_BENCHMARK_BLOCKED")
        direct_samples.append((time.perf_counter_ns() - t0) / 1_000_000)

    bench_functional_adapter = DeterministicAdapter()
    bench_functional_verifier = DeterministicVerifier()
    bench_functional = build_functional_workflow(
        adapter=bench_functional_adapter,
        verifier=bench_functional_verifier,
        checkpointer=InMemorySaver(),
    )
    for i in range(BENCHMARK_WARMUPS):
        result = bench_functional.invoke(
            base_payload,
            config={"configurable": {"thread_id": f"r02e-warm-{i}"}},
        )
        if result.get("status") != "PASS":
            raise AssertionError("R02E_FUNCTIONAL_WARMUP_BLOCKED")
    functional_samples: list[float] = []
    for i in range(BENCHMARK_RUNS):
        t0 = time.perf_counter_ns()
        result = bench_functional.invoke(
            base_payload,
            config={"configurable": {"thread_id": f"r02e-bench-{i}"}},
        )
        if result.get("status") != "PASS":
            raise AssertionError("R02E_FUNCTIONAL_BENCHMARK_BLOCKED")
        functional_samples.append((time.perf_counter_ns() - t0) / 1_000_000)

    direct_median = statistics.median(direct_samples)
    functional_median = statistics.median(functional_samples)
    median_overhead = functional_median - direct_median
    overhead_within_budget = median_overhead <= SYNTHETIC_OVERHEAD_BUDGET_MS

    direct_signature = inspect.signature(execute_profile_runtime)
    direct_parameter_names = set(direct_signature.parameters)
    direct_runner_native_hitl_parameters = bool(
        direct_parameter_names.intersection({"requires_human", "resume", "checkpoint", "thread_id"})
    )

    direct_loc = nonblank_noncomment_loc(inspect.getsource(execute_profile_runtime))
    functional_builder_loc = nonblank_noncomment_loc(inspect.getsource(build_functional_workflow))

    adoption_criteria = {
        "exact_final_s26_result_parity": exact_result_parity,
        "nontransient_fail_closed_parity": fail_closed_parity,
        "selective_transient_auto_recovery": transient_recovery_gain,
        "hitl_pause_resume_and_reject": hitl_paused_before_execution and hitl_resume_pass and hitl_reject_fail_closed,
        "checkpoint_history_present": checkpoint_history_count >= 1,
        "synthetic_overhead_within_5ms_budget": overhead_within_budget,
    }
    decision_pass = all(adoption_criteria.values())

    report = {
        "schema": "LF_LANGGRAPH_R02E_FINAL_S26_VALUE_COMPARE_V1",
        "gate": "ADOPT-R02-E",
        "s26_candidate_sha": S26_CANDIDATE_SHA,
        "langgraph_pin": LANGGRAPH_PIN,
        "comparison_scope": "FINAL_S26_CODE_LEVEL_RUNTIME_ORCHESTRATION_COMPARISON",
        "model_called": False,
        "external_model_network_calls": 0,
        "production_effect": False,
        "semantic_authority_owner": "LF",
        "exact_result_parity": exact_result_parity,
        "direct_result_sha256": direct_result_sha,
        "functional_result_sha256": functional_result_sha,
        "nontransient_fail_closed": {
            "direct": direct_block,
            "functional": functional_block,
            "exact_parity": fail_closed_parity,
            "direct_attempts": direct_block_adapter.calls,
            "functional_attempts": functional_block_adapter.calls,
        },
        "transient_failure_comparison": {
            "direct_first_call": direct_transient,
            "direct_attempts": direct_transient_adapter.calls,
            "functional_result_status": functional_transient.get("status"),
            "functional_attempts": functional_transient_adapter.calls,
            "automatic_recovery_gain": transient_recovery_gain,
        },
        "hitl_comparison": {
            "direct_runner_native_hitl_parameters": direct_runner_native_hitl_parameters,
            "functional_paused_before_lf_execution": hitl_paused_before_execution,
            "functional_resume_pass": hitl_resume_pass,
            "functional_reject_fail_closed": hitl_reject_fail_closed,
        },
        "checkpoint_comparison": {
            "direct_runner_checkpoint_history": "NONE_INSIDE_EXECUTE_PROFILE_RUNTIME",
            "functional_checkpoint_history_count": checkpoint_history_count,
            "checkpointer_used": "InMemorySaver",
            "durable_postgres_proven": False,
        },
        "synthetic_latency_ms": {
            "warmups": BENCHMARK_WARMUPS,
            "measured_runs": BENCHMARK_RUNS,
            "lf_direct_median": round(direct_median, 6),
            "lf_direct_p95": round(percentile(direct_samples, 0.95), 6),
            "langgraph_functional_median": round(functional_median, 6),
            "langgraph_functional_p95": round(percentile(functional_samples, 0.95), 6),
            "absolute_median_overhead": round(median_overhead, 6),
            "overhead_budget_ms": SYNTHETIC_OVERHEAD_BUDGET_MS,
            "overhead_within_budget": overhead_within_budget,
            "speed_winner": "LF_DIRECT" if direct_median <= functional_median else "LANGGRAPH_FUNCTIONAL",
        },
        "code_surface": {
            "lf_execute_profile_runtime_nonblank_noncomment_lines": direct_loc,
            "r02e_functional_builder_nonblank_noncomment_lines": functional_builder_loc,
            "interpretation": "Not a total-code replacement metric: LangGraph adds orchestration around LF; semantic runtime remains LF-owned.",
        },
        "value_summary": {
            "semantic_quality": "TIE_SAME_LF_RESULT",
            "raw_speed": "LF_DIRECT",
            "selective_retry": "LANGGRAPH_FUNCTIONAL",
            "hitl_pause_resume": "LANGGRAPH_FUNCTIONAL",
            "checkpoint_history": "LANGGRAPH_FUNCTIONAL",
            "maintenance_savings": "NOT_PROVEN_BY_THIS_GATE",
            "n8n_business_orchestration_replacement": False,
        },
        "adoption_criteria": adoption_criteria,
        "decision": (
            "ADOPT_LANGGRAPH_FUNCTIONAL_FOR_BOUNDED_CODE_LEVEL_STATEFUL_ORCHESTRATION"
            if decision_pass
            else "NO_ADOPT_OR_REPAIR_REQUIRED"
        ),
        "decision_scope": "NOT_SEMANTIC_AUTHORITY_NOT_N8N_REPLACEMENT_NOT_PRODUCTION_ACTIVATION",
        "production_activation_ready": False,
        "remaining_production_gate": "DURABLE_CHECKPOINTER_AND_OPERATIONAL_ROLLBACK_FIT",
        "status": "PASS" if decision_pass else "FAIL",
    }

    if not decision_pass:
        raise AssertionError(json.dumps(report, sort_keys=True))

    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
