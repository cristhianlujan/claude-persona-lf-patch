"""Microbenchmark for pure READ_ONLY resolver only; not Router/DB E2E latency."""
from __future__ import annotations

import json
import statistics
import time
from functools import lru_cache

from change_impact_resolver_readonly import ResolverContext, resolve
from run_resolver_tests import apply_adjudication, parse_gold

ROWS = apply_adjudication(parse_gold())
CTX = ResolverContext(api_behavioral_contract=True, operation_schema_authority_materialized=False)


def direct_batch():
    return [resolve(row["case_family"], row["mutation"], CTX) for row in ROWS]


@lru_cache(maxsize=256)
def cached_one(case_family: str, mutation: str, behavioral: bool, schema: bool):
    return resolve(case_family, mutation, ResolverContext(behavioral, schema))


def cached_batch():
    return [cached_one(row["case_family"], row["mutation"], True, False) for row in ROWS]


def sample(fn, iterations: int):
    out = []
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        fn()
        out.append((time.perf_counter_ns() - t0) / 1_000_000)
    return out


def pct(xs, q):
    xs = sorted(xs)
    idx = min(len(xs) - 1, max(0, int((len(xs) - 1) * q)))
    return xs[idx]


def main():
    cold = sample(direct_batch, 200)
    cached_one.cache_clear()
    cached_batch()  # prime exactly 50 keys
    warm = sample(cached_batch, 500)
    payload = [{
        "case_family": r["case_family"],
        "mutation": r["mutation"],
        "api_behavioral_contract": True,
        "operation_schema_authority_materialized": False,
    } for r in ROWS]
    context_bytes = len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    depths = [x.depth for x in direct_batch()]
    result = {
        "scope": "PURE_RESOLVER_50_CASE_BATCH_NOT_ROUTER_E2E",
        "cold_direct_ms": {"p50": statistics.median(cold), "p95": pct(cold, .95), "min": min(cold), "max": max(cold)},
        "warm_cached_ms": {"p50": statistics.median(warm), "p95": pct(warm, .95), "min": min(warm), "max": max(warm)},
        "cache": cached_one.cache_info()._asdict(),
        "context_bytes": context_bytes,
        "context_tokens": None,
        "depth": {"min": min(depths), "max": max(depths)},
    }
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
