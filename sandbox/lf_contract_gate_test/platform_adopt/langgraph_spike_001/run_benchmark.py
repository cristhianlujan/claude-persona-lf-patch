#!/usr/bin/env python3
"""Micro-benchmark for orchestration overhead only; no model/network calls."""
from __future__ import annotations

import json
import statistics
import time

from langgraph.checkpoint.memory import InMemorySaver

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
    counter = {"value": 0}

    def graph_call():
        counter["value"] += 1
        return graph.invoke(
            payload(),
            config={"configurable": {"thread_id": f"benchm{counter['value']}"}},
        )

    baseline_sample = current()
    graph_sample = graph_call()
    if graph_sample["runtime_result"] != baseline_sample:
        raise SystemExit("SPIKE_BENCHMARK_PARITY_FAILED")

    current_ms = _measure(current)
    graph_ms = _measure(graph_call)
    current_median = statistics.median(current_ms)
    graph_median = statistics.median(graph_ms)

    report = {
        "schema": "lf-langgraph-spike-benchmark/v1",
        "spike_id": "LF_LANGGRAPH_SPIKE_001",
        "mode": "DETERMINISTIC_NO_MODEL_NO_NETWORK",
        "runs": RUNS,
        "warmup": WARMUP,
        "payload_parity": True,
        "current_runtime": {
            "median_ms": round(current_median, 6),
            "p95_ms": round(_p95(current_ms), 6),
        },
        "langgraph_wrapper": {
            "median_ms": round(graph_median, 6),
            "p95_ms": round(_p95(graph_ms), 6),
        },
        "orchestration_overhead": {
            "median_ms": round(graph_median - current_median, 6),
            "ratio": None if current_median == 0 else round(graph_median / current_median, 4),
        },
        "claim_boundary": (
            "Measures Python orchestration overhead only. It does not measure "
            "real model latency, provider latency, durable Postgres checkpointing, "
            "or production throughput."
        ),
    }
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
