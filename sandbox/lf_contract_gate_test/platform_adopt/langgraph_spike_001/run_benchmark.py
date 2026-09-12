#!/usr/bin/env python3
"""Micro-benchmark for orchestration overhead only; no model/network calls."""
from __future__ import annotations

import inspect
import json
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
RUNTIME = REPO / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
for path in (str(RUNTIME), str(HERE)):
    if path not in sys.path:
        sys.path.insert(0, path)

from langgraph.checkpoint.memory import InMemorySaver

from langgraph_functional_spike import build_functional_workflow
from langgraph_profile_spike import build_spike_graph
from test_langgraph_profile_spike import (
    DeterministicAdapter,
    DeterministicVerifier,
    baseline,
    payload,
)

WARMUP = 10
RUNS = 100


def _p95(values: list[float]) -> float:
    ordered = sorted(values)
    return ordered[max(0, min(len(ordered) - 1, int(len(ordered) * 0.95) - 1))]


def _measure(fn) -> list[float]:
    values = []
    for _ in range(WARMUP):
        fn()
    for _ in range(RUNS):
        started = time.perf_counter_ns()
        fn()
        values.append((time.perf_counter_ns() - started) / 1_000_000)
    return values


def _source_metrics(fn) -> dict[str, int]:
    lines = inspect.getsource(fn).splitlines()
    material = [
        line
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    ]
    return {
        "physical_lines": len(lines),
        "nonblank_noncomment_lines": len(material),
    }


def main() -> int:
    verifier = DeterministicVerifier()
    current_adapter = DeterministicAdapter()
    current = lambda: baseline(current_adapter, verifier)

    graph_adapter = DeterministicAdapter()
    graph = build_spike_graph(
        adapter=graph_adapter,
        attestation_verifier=verifier,
        checkpointer=InMemorySaver(),
    )

    functional_adapter = DeterministicAdapter()
    functional = build_functional_workflow(
        adapter=functional_adapter,
        attestation_verifier=verifier,
        checkpointer=InMemorySaver(),
    )

    counters = {"graph": 0, "functional": 0}

    def graph_call():
        counters["graph"] += 1
        return graph.invoke(
            payload(),
            config={"configurable": {"thread_id": f"bench-graph-{counters['graph']}"}},
        )

    def functional_call():
        counters["functional"] += 1
        return functional.invoke(
            payload(),
            config={
                "configurable": {
                    "thread_id": f"bench-functional-{counters['functional']}"
                }
            },
        )

    baseline_sample = current()
    graph_sample = graph_call()
    functional_sample = functional_call()
    if graph_sample["runtime_result"] != baseline_sample:
        raise SystemExit("SPIKE_BENCHMARK_STATEGRAPH_PARITY_FAILED")
    if functional_sample["runtime_result"] != baseline_sample:
        raise SystemExit("SPIKE_BENCHMARK_FUNCTIONAL_PARITY_FAILED")

    current_ms = _measure(current)
    graph_ms = _measure(graph_call)
    functional_ms = _measure(functional_call)

    current_median = statistics.median(current_ms)
    graph_median = statistics.median(graph_ms)
    functional_median = statistics.median(functional_ms)

    report = {
        "schema": "lf-langgraph-api-comparison/v2",
        "spike_id": "LF_LANGGRAPH_SPIKE_001_R02B",
        "mode": "DETERMINISTIC_NO_MODEL_NO_NETWORK",
        "runs": RUNS,
        "warmup": WARMUP,
        "payload_parity": True,
        "current_runtime": {
            "median_ms": round(current_median, 6),
            "p95_ms": round(_p95(current_ms), 6),
        },
        "stategraph_wrapper": {
            "median_ms": round(graph_median, 6),
            "p95_ms": round(_p95(graph_ms), 6),
            "overhead_ms": round(graph_median - current_median, 6),
            "builder_source": _source_metrics(build_spike_graph),
        },
        "functional_wrapper": {
            "median_ms": round(functional_median, 6),
            "p95_ms": round(_p95(functional_ms), 6),
            "overhead_ms": round(functional_median - current_median, 6),
            "builder_source": _source_metrics(build_functional_workflow),
        },
        "functional_vs_stategraph": {
            "median_delta_ms": round(functional_median - graph_median, 6),
            "source_nonblank_line_delta": (
                _source_metrics(build_functional_workflow)["nonblank_noncomment_lines"]
                - _source_metrics(build_spike_graph)["nonblank_noncomment_lines"]
            ),
        },
        "claim_boundary": (
            "Measures Python orchestration overhead and wrapper source surface only. "
            "It does not measure real model/provider latency, durable Postgres "
            "checkpointing, production throughput, or maintenance cost."
        ),
    }
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
