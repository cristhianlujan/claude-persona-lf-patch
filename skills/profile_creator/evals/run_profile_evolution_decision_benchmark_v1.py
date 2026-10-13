#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import sys
import time
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def canonical(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--fixture", required=True)
    ap.add_argument("--methods", required=True)
    ap.add_argument("--baseline-source", required=True)
    ap.add_argument("--candidate-source", required=True)
    ap.add_argument("--assessment-dir", required=True)
    ap.add_argument("--selector-dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    cases_path = Path(args.cases).resolve()
    fixture_path = Path(args.fixture).resolve()
    methods_path = Path(args.methods).resolve()
    baseline_path = Path(args.baseline_source).resolve()
    candidate_path = Path(args.candidate_source).resolve()

    # The raw runner has no oracle argument and never opens an oracle path.
    cases = json.loads(cases_path.read_text(encoding="utf-8"))
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    methods = json.loads(methods_path.read_text(encoding="utf-8"))

    sys.path.insert(0, str(Path(args.assessment_dir).resolve()))
    sys.path.insert(0, str(Path(args.selector_dir).resolve()))

    # Exact-source planner imports expect these modules. They are inert stubs here;
    # the planner globals are replaced immediately with frozen fixture functions.
    import types
    preflight_stub = types.ModuleType("evaluate_s26_learning_preflight")
    preflight_stub.evaluate_learning_preflight = lambda *a, **k: copy.deepcopy(fixture["learning_preflight_result"])
    sys.modules["evaluate_s26_learning_preflight"] = preflight_stub

    baseline_stub = types.ModuleType("evaluate_s26_profile_baseline")
    baseline_stub.evaluate = lambda *a, **k: {}
    sys.modules["evaluate_s26_profile_baseline"] = baseline_stub

    baseline_mod = load_module("peb_baseline_plan", baseline_path)
    candidate_mod = load_module("peb_candidate_plan", candidate_path)

    rows = []
    for case in cases["cases"]:
        fixture_name = case["structural_fixture"]
        structural = copy.deepcopy(fixture["structural_fixtures"][fixture_name])

        def structural_eval(*_args, **_kwargs):
            return copy.deepcopy(structural)

        def preflight_eval(*_args, **_kwargs):
            return copy.deepcopy(fixture["learning_preflight_result"])

        baseline_mod.evaluate = structural_eval
        baseline_mod.evaluate_learning_preflight = preflight_eval
        candidate_mod.evaluate_s26 = structural_eval
        candidate_mod.evaluate_learning_preflight = preflight_eval

        t0 = time.perf_counter_ns()
        baseline = baseline_mod.build_plan(
            Path("."),
            case["fixture_profile_slug"],
            {"schema": "BENCHMARK_PREFLIGHT_STUB_V1"},
            current_revision=cases["repository_profile_snapshot_sha"],
        )
        t1 = time.perf_counter_ns()

        assessment_payload = copy.deepcopy(case["case_input"])
        t2 = time.perf_counter_ns()
        candidate = candidate_mod.build_evolution_plan(
            Path("."),
            case["fixture_profile_slug"],
            {"schema": "BENCHMARK_PREFLIGHT_STUB_V1"},
            assessment_payload,
            fixture["capability_catalog"],
            fixture["capability_policy"],
            methods,
            current_revision=cases["repository_profile_snapshot_sha"],
        )
        t3 = time.perf_counter_ns()

        rows.append({
            "case_id": case["case_id"],
            "stratum": case["stratum"],
            "holdout": case["holdout"],
            "structural_fixture": fixture_name,
            "baseline_arm": case["baseline_arm"],
            "candidate_arm": case["candidate_arm"],
            "baseline_output": baseline,
            "candidate_output": candidate,
            "timing_ns": {
                "baseline": t1 - t0,
                "candidate": t3 - t2,
            },
        })

    raw = {
        "schema": "PROFILE_EVOLUTION_DECISION_BENCHMARK_RAW_V1",
        "generation_id": cases["generation_id"],
        "generation": cases["generation"],
        "benchmark_scope": cases["benchmark_scope"],
        "repository_profile_snapshot_sha": cases["repository_profile_snapshot_sha"],
        "case_count": len(rows),
        "holdout_count": sum(1 for r in rows if r["holdout"]),
        "oracle_opened": False,
        "scores_materialized": False,
        "write_authorized": False,
        "runtime_activation": False,
        "production_activation": False,
        "sources": {
            "cases_sha256": sha256_file(cases_path),
            "fixture_sha256": sha256_file(fixture_path),
            "methods_sha256": sha256_file(methods_path),
            "baseline_source_sha256": sha256_file(baseline_path),
            "candidate_source_sha256": sha256_file(candidate_path),
        },
        "rows": rows,
    }
    raw["raw_sha256"] = hashlib.sha256(canonical(raw)).hexdigest()
    Path(args.out).write_text(json.dumps(raw, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": "RAW_FROZEN",
        "case_count": raw["case_count"],
        "holdout_count": raw["holdout_count"],
        "raw_sha256": raw["raw_sha256"],
        "oracle_opened": raw["oracle_opened"],
        "scores_materialized": raw["scores_materialized"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
