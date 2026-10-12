#!/usr/bin/env python3
"""S36 WP5 local/sandbox performance baseline runner.

PASS/FAIL is emitted only where an explicit threshold policy supplies a limit.
Missing limits are NOT_COVERED. This runner never exercises production-like runtime.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import platform
import resource
import statistics
import sys
import time
import tracemalloc
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def pct(values: list[float], p: float) -> float:
    values = sorted(values)
    if not values:
        return 0.0
    pos = (len(values) - 1) * p
    lo = int(pos)
    hi = min(lo + 1, len(values) - 1)
    frac = pos - lo
    return values[lo] * (1 - frac) + values[hi] * frac


def load_callable(path: Path, name: str) -> Callable[[dict[str, Any]], Any]:
    spec = importlib.util.spec_from_file_location("s36_wp5_target", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("TARGET_IMPORT_SPEC_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    fn = getattr(module, name, None)
    if not callable(fn):
        raise RuntimeError(f"TARGET_CALLABLE_MISSING:{name}")
    return fn


def load_cases(path: Path) -> list[dict[str, Any]]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    rows = doc.get("cases") if isinstance(doc, dict) else doc
    if not isinstance(rows, list) or not rows:
        raise RuntimeError("FIXTURE_CASES_MISSING")
    return [
        {k: v for k, v in row.items() if k not in {"case_id", "case_family"}}
        for row in rows
        if isinstance(row, dict)
    ]


def gate_le(value: float, limit: Any) -> str:
    return "NOT_COVERED" if limit is None else ("PASS" if value <= float(limit) else "FAIL")


def gate_ge(value: float, limit: Any) -> str:
    return "NOT_COVERED" if limit is None else ("PASS" if value >= float(limit) else "FAIL")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--target", type=Path, required=True)
    p.add_argument("--callable", default="resolve_change")
    p.add_argument("--fixture", type=Path, required=True)
    p.add_argument("--threshold-policy", type=Path, required=True)
    p.add_argument("--rounds", type=int, default=3)
    p.add_argument("--warmup-repetitions", type=int, default=100)
    p.add_argument("--measured-repetitions", type=int, default=400)
    p.add_argument("--resource-repetitions", type=int, default=100)
    p.add_argument("--output", type=Path)
    args = p.parse_args()

    fn = load_callable(args.target, args.callable)
    cases = load_cases(args.fixture)
    policy = json.loads(args.threshold_policy.read_text(encoding="utf-8"))
    thresholds = policy.get("thresholds", {})
    baseline_hashes = [hashlib.sha256(canonical(fn(case))).hexdigest() for case in cases]

    rounds: list[dict[str, Any]] = []
    total_errors = 0
    total_mismatches = 0
    for round_no in range(1, args.rounds + 1):
        for _ in range(args.warmup_repetitions):
            for case in cases:
                fn(case)
        samples: list[float] = []
        errors = 0
        mismatches = 0
        wall0 = time.perf_counter()
        cpu0 = time.process_time()
        for _ in range(args.measured_repetitions):
            for idx, case in enumerate(cases):
                t0 = time.perf_counter_ns()
                try:
                    result = fn(case)
                except Exception:
                    errors += 1
                    continue
                samples.append((time.perf_counter_ns() - t0) / 1_000_000.0)
                if hashlib.sha256(canonical(result)).hexdigest() != baseline_hashes[idx]:
                    mismatches += 1
        wall_s = time.perf_counter() - wall0
        cpu_s = time.process_time() - cpu0
        total_errors += errors
        total_mismatches += mismatches
        rounds.append({
            "round": round_no,
            "samples": len(samples),
            "p50_ms": pct(samples, 0.50),
            "p95_ms": pct(samples, 0.95),
            "p99_ms": pct(samples, 0.99),
            "max_ms": max(samples) if samples else None,
            "operations_per_second": len(samples) / wall_s if wall_s else None,
            "wall_ms": wall_s * 1000,
            "cpu_ms": cpu_s * 1000,
            "errors": errors,
            "output_mismatches": mismatches,
        })

    rss_before = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    tracemalloc.start()
    resource_wall0 = time.perf_counter()
    for _ in range(args.resource_repetitions):
        for case in cases:
            fn(case)
    resource_wall_ms = (time.perf_counter() - resource_wall0) * 1000
    current_bytes, peak_bytes = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    rss_after = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss

    median_p95 = statistics.median(r["p95_ms"] for r in rounds)
    median_throughput = statistics.median(r["operations_per_second"] for r in rounds)
    reliability_policy = thresholds.get("repeated_reliability") or {}
    reliability_status = "NOT_COVERED"
    if reliability_policy:
        reliability_status = "PASS"
        if total_errors > int(reliability_policy.get("max_errors", 0)):
            reliability_status = "FAIL"
        if total_mismatches > int(reliability_policy.get("max_output_mismatches", 0)):
            reliability_status = "FAIL"

    resource_checks: list[str] = []
    if thresholds.get("resource_peak_alloc_max_bytes") is not None:
        resource_checks.append(gate_le(peak_bytes, thresholds["resource_peak_alloc_max_bytes"]))
    if thresholds.get("resource_rss_delta_max_kib") is not None:
        resource_checks.append(gate_le(max(0, rss_after - rss_before), thresholds["resource_rss_delta_max_kib"]))
    resource_status = "NOT_COVERED" if not resource_checks else ("FAIL" if "FAIL" in resource_checks else "PASS")

    report = {
        "schema": "S36_WP5_LOCAL_PERFORMANCE_BASELINE_V1",
        "executed_at_utc": datetime.now(timezone.utc).isoformat(),
        "environment": {"class": "LOCAL_SANDBOX", "python": sys.version.split()[0], "implementation": platform.python_implementation(), "platform": platform.platform(), "machine": platform.machine()},
        "target": {"path": str(args.target), "sha256": sha256_file(args.target), "callable": args.callable},
        "fixture": {"path": str(args.fixture), "sha256": sha256_file(args.fixture), "cases": len(cases), "association_fields_removed": ["case_id", "case_family"]},
        "workload": {"rounds": args.rounds, "warmup_repetitions_per_round": args.warmup_repetitions, "measured_repetitions_per_round": args.measured_repetitions, "samples_per_round": len(cases) * args.measured_repetitions},
        "round_results": rounds,
        "summary": {"median_p95_ms": median_p95, "median_operations_per_second": median_throughput, "total_errors": total_errors, "total_output_mismatches": total_mismatches},
        "resource_behavior": {"measurement_separated_from_latency_loop": True, "calls": len(cases) * args.resource_repetitions, "wall_ms": resource_wall_ms, "tracemalloc_current_bytes": current_bytes, "tracemalloc_peak_bytes": peak_bytes, "ru_maxrss_before_kib_linux": rss_before, "ru_maxrss_after_kib_linux": rss_after, "rss_delta_kib_linux": max(0, rss_after - rss_before)},
        "threshold_policy": policy,
        "dimension_verdicts": {
            "latency": gate_le(median_p95, thresholds.get("latency_p95_max_ms")),
            "throughput": gate_ge(median_throughput, thresholds.get("throughput_min_operations_per_second")),
            "repeated_reliability": reliability_status,
            "resource_behavior": resource_status,
            "timeout_behavior": "NOT_COVERED",
            "production_like": "BLOCK"
        },
        "performance_pass_claimed": False,
        "production_like_authorization": False,
        "notes": [
            "Latency/throughput are measurements, not SLOs unless an explicit threshold policy supplies a gate.",
            "Resource instrumentation is isolated from the latency loop to avoid perturbing timing.",
            "This runner does not exercise production-like or remote runtimes."
        ]
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    sys.stdout.write(rendered)
    return 2 if "FAIL" in report["dimension_verdicts"].values() else 0


if __name__ == "__main__":
    raise SystemExit(main())
