from __future__ import annotations

import json
import math
import time

import test_s26_family_objective_matrix_v3 as v3


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    pos = (len(ordered) - 1) * p
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def run_batch(resolver, runtime, rows) -> float:
    started = time.perf_counter_ns()
    for row in rows:
        resolver.resolve_change_impact(str(row["family"]), str(row["mutation"]), runtime)
    return (time.perf_counter_ns() - started) / 1_000_000.0


def main() -> None:
    resolver = v3.load_resolver_module()
    rows = v3.load_gold()
    assert len(rows) == 50
    runtime = resolver.RuntimeAuthority(
        behavioral_contract_present=True,
        operation_schema_authority_materialized=False,
    )

    cold_batch_ms = run_batch(resolver, runtime, rows)
    warm_batches_ms = [run_batch(resolver, runtime, rows) for _ in range(25)]

    per_case_us: list[float] = []
    for _ in range(10):
        for row in rows:
            started = time.perf_counter_ns()
            resolver.resolve_change_impact(str(row["family"]), str(row["mutation"]), runtime)
            per_case_us.append((time.perf_counter_ns() - started) / 1000.0)

    metrics = {
        "scope": "LOCAL_DETERMINISTIC_RESOLVER_PRE_CERTIFICATION",
        "cases_per_batch": 50,
        "cold_batch_ms": cold_batch_ms,
        "warm_batch_p50_ms": percentile(warm_batches_ms, 0.50),
        "warm_batch_p95_ms": percentile(warm_batches_ms, 0.95),
        "per_case_p50_us": percentile(per_case_us, 0.50),
        "per_case_p95_us": percentile(per_case_us, 0.95),
        "samples": {
            "warm_batches": len(warm_batches_ms),
            "per_case": len(per_case_us),
        },
        "final_budget_bound": False,
        "final_budget_reason": "Bind only after PR #682 and PR #681 migration/readback produce the final stable integrated S26 candidate.",
        "statistics": "DESCRIPTIVE_ONLY; NO_GLMM_GEE_WITHOUT_STOCHASTIC_MODEL_REPEATS",
    }
    assert all(math.isfinite(float(metrics[key])) and float(metrics[key]) >= 0 for key in (
        "cold_batch_ms", "warm_batch_p50_ms", "warm_batch_p95_ms", "per_case_p50_us", "per_case_p95_us"
    ))
    print(json.dumps(metrics, sort_keys=True))


if __name__ == "__main__":
    main()
