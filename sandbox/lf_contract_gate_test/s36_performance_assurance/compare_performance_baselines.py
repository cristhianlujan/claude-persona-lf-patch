#!/usr/bin/env python3
"""Compare two S36 WP5 baseline receipts without inventing gates."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def status_le(value: float, limit: Any) -> str:
    return "NOT_COVERED" if limit is None else ("PASS" if value <= float(limit) else "FAIL")


def status_ge(value: float, limit: Any) -> str:
    return "NOT_COVERED" if limit is None else ("PASS" if value >= float(limit) else "FAIL")


def reliability_status(summary: dict[str, Any], policy: dict[str, Any]) -> str:
    reliability = (policy.get("thresholds") or {}).get("repeated_reliability")
    if not isinstance(reliability, dict) or not reliability.get("provenance"):
        return "NOT_COVERED"
    max_errors = reliability.get("max_errors")
    max_mismatches = reliability.get("max_output_mismatches")
    if max_errors is None or max_mismatches is None:
        return "NOT_COVERED"
    if int(summary.get("total_errors", 0)) > int(max_errors):
        return "FAIL"
    if int(summary.get("total_output_mismatches", 0)) > int(max_mismatches):
        return "FAIL"
    return "PASS"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--reference", type=Path, required=True)
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--policy", type=Path, required=True)
    p.add_argument("--output", type=Path)
    args = p.parse_args()

    ref = json.loads(args.reference.read_text(encoding="utf-8"))
    cur = json.loads(args.candidate.read_text(encoding="utf-8"))
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    limits = policy.get("regression_limits", {})

    rp95 = float(ref["summary"]["median_p95_ms"])
    cp95 = float(cur["summary"]["median_p95_ms"])
    rt = float(ref["summary"]["median_operations_per_second"])
    ct = float(cur["summary"]["median_operations_per_second"])
    latency_ratio = cp95 / rp95 if rp95 else None
    throughput_ratio = ct / rt if rt else None

    verdicts = {
        "latency_regression": status_le(latency_ratio, limits.get("max_p95_ratio")) if latency_ratio is not None else "NOT_COVERED",
        "throughput_regression": status_ge(throughput_ratio, limits.get("min_throughput_ratio")) if throughput_ratio is not None else "NOT_COVERED",
        "repeated_reliability": reliability_status(cur.get("summary", {}), policy),
        "resource_regression": "NOT_COVERED",
        "timeout_regression": "NOT_COVERED",
        "production_like": "BLOCK",
    }
    out = {
        "schema": "S36_WP5_PERFORMANCE_REGRESSION_COMPARISON_V1",
        "reference": str(args.reference),
        "candidate": str(args.candidate),
        "policy": policy,
        "deltas": {
            "reference_median_p95_ms": rp95,
            "candidate_median_p95_ms": cp95,
            "p95_ratio": latency_ratio,
            "reference_median_operations_per_second": rt,
            "candidate_median_operations_per_second": ct,
            "throughput_ratio": throughput_ratio,
        },
        "verdicts": verdicts,
        "performance_pass_claimed": False,
        "rule": "No comparison becomes PASS/FAIL unless the supplied policy contains a provenance-backed limit for that dimension."
    }
    rendered = json.dumps(out, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 2 if "FAIL" in verdicts.values() else 0


if __name__ == "__main__":
    raise SystemExit(main())
