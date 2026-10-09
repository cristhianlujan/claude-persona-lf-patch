#!/usr/bin/env python3
"""M8.10 SLO_OVER_LIMIT_NEGATIVE: an IG SLO record with p95 >= the Edge limit (150 s), or without enough samples, is rejected.
Judge over IG_M8_10_SLO_SNAPSHOT_V1 (live aggregates read-only: Validator compute per invocation from input_validator_chunk_timings,
and total wall-clock from input_readiness_runs). Baseline (compute per invocation) must be accepted; every mutation and the live
wall-clock record must be rejected. No writes."""
from __future__ import annotations
import argparse, copy, json, os, sys
from pathlib import Path

TEST_CODE = "ENG_M8_10_SLO_OVER_LIMIT_NEGATIVE"
PCTS = ("p50_ms", "p95_ms", "p99_ms")


def judge(slo: dict, limit_ms: int, min_samples: int) -> list[str]:
    p: list[str] = []
    if not isinstance(slo.get("sample_count"), int) or isinstance(slo.get("sample_count"), bool) or slo["sample_count"] < min_samples:
        p.append("SAMPLES_INSUFFICIENT")
    vals = []
    for k in PCTS:
        v = slo.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0:
            p.append("PERCENTILE_INVALID:" + k)
        else:
            vals.append(v)
    if len(vals) == 3 and not (vals[0] <= vals[1] <= vals[2]):
        p.append("PERCENTILES_NOT_MONOTONIC")
    if isinstance(slo.get("p95_ms"), (int, float)) and not isinstance(slo.get("p95_ms"), bool) and slo["p95_ms"] >= limit_ms:
        p.append("P95_AT_OR_OVER_LIMIT")
    if not slo.get("corpus_sha256"):
        p.append("CORPUS_SHA_MISSING")
    return p


def mutations(slo: dict, limit_ms: int):
    def m(name, fn):
        c = copy.deepcopy(slo); fn(c); return name, c
    yield m("P95_EQUALS_LIMIT", lambda c: c.update(p95_ms=limit_ms, p99_ms=limit_ms + 1))
    yield m("P95_OVER_LIMIT", lambda c: c.update(p95_ms=limit_ms + 1, p99_ms=limit_ms + 2))
    yield m("TOO_FEW_SAMPLES", lambda c: c.update(sample_count=2))
    yield m("NO_SAMPLES", lambda c: c.update(sample_count=0))
    yield m("PERCENTILE_MISSING", lambda c: c.pop("p99_ms"))
    yield m("NEGATIVE_PERCENTILE", lambda c: c.update(p50_ms=-1))
    yield m("NOT_MONOTONIC", lambda c: c.update(p50_ms=c["p99_ms"] + 1))
    yield m("NO_CORPUS_SHA", lambda c: c.update(corpus_sha256=""))


def run(s: dict) -> dict:
    limit, mins = s["edge_limit_ms"], s["min_samples"]
    base = judge(s["compute_per_invocation"], limit, mins)
    res = []
    for name, c in mutations(s["compute_per_invocation"], limit):
        pr = judge(c, limit, mins)
        res.append({"mutation": name, "detected": bool(pr), "problems": pr[:2]})
    wall = judge(s["wall_clock_total"], limit, mins)  # live record: must be rejected today
    ok = not base and all(r["detected"] for r in res) and bool(wall)
    return {
        "test_code": TEST_CODE, "baseline_problems": base, "live_wall_clock_rejected": bool(wall), "live_wall_clock_problems": wall,
        "mutations_total": len(res), "mutations_detected": sum(r["detected"] for r in res), "mutations": res,
        "observed": {
            "test_passed": ok, "test_exit_code": 0 if ok else 1,
            "semantic_authority_bound": bool(s.get("schema") == "IG_M8_10_SLO_SNAPSHOT_V1" and s.get("limit_source") == "M8.0/INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1"),
            "adversarial_case_executed": len(res) == 8,
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--input")
    a = ap.parse_args()
    raw = a.input or os.environ.get("ENGINEERING_DECLARED_INPUT_JSON")
    if not raw:
        print(json.dumps({"observed": {"test_passed": False, "test_exit_code": 2, "semantic_authority_bound": False, "adversarial_case_executed": False}, "problems": ["NO_INPUT"]})); return 2
    s = json.loads(Path(raw).read_text()) if not raw.lstrip().startswith("{") else json.loads(raw)
    out = run(s); print(json.dumps(out, indent=1, sort_keys=True)); return out["observed"]["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
