#!/usr/bin/env python3
from __future__ import annotations

import ast
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name: str):
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def test_contract_is_single_matrix_and_non_productive():
    contract = load("performance_contract_v1.json")
    assert contract["canonical_matrix"] == "S36_CANONICAL_LF_TEST_MATRIX"
    assert contract["principles"]["single_matrix_only"] is True
    assert contract["principles"]["production_like_requires_explicit_authorization"] is True
    assert contract["principles"]["scheduler_or_productive_runtime_created"] is False
    assert contract["principles"]["owner_semantics_mutated"] is False


def test_no_invented_thresholds_for_local_resolver():
    policy = load("threshold_policy_change_impact_resolver_v1.json")
    thresholds = policy["thresholds"]
    assert thresholds["latency_p95_max_ms"] is None
    assert thresholds["throughput_min_operations_per_second"] is None
    assert thresholds["resource_peak_alloc_max_bytes"] is None
    assert thresholds["resource_rss_delta_max_kib"] is None
    assert thresholds["timeout_seconds"] is None
    reliability = thresholds["repeated_reliability"]
    assert reliability["max_errors"] == 0
    assert reliability["max_output_mismatches"] == 0
    assert reliability["provenance"]["type"] == "EXISTING_CONTRACT"


def test_baseline_never_claims_global_performance_pass():
    baseline = load("baseline_change_impact_resolver_local_20260914.json")
    verdicts = baseline["dimension_verdicts"]
    assert baseline["performance_pass_claimed"] is False
    assert baseline["production_like_authorization"] is False
    assert verdicts == {
        "latency": "NOT_COVERED",
        "throughput": "NOT_COVERED",
        "repeated_reliability": "PASS",
        "resource_behavior": "NOT_COVERED",
        "timeout_behavior": "NOT_COVERED",
        "production_like": "BLOCK",
    }
    assert baseline["execution"]["measured_samples_total"] == 60000
    assert baseline["summary"]["total_errors"] == 0
    assert baseline["summary"]["total_output_mismatches"] == 0


def test_persistence_proposal_reuses_existing_test_platform():
    proposal = load("persistence_proposal_v1.json")
    assert proposal["status"] == "PROPOSAL_ONLY_NOT_APPLIED"
    assert proposal["new_strategy_required"] is False
    assert proposal["new_matrix_required"] is False
    assert proposal["write_status"] == "NO_SUPABASE_WRITE_PERFORMED_BY_WP5"
    storage = proposal["reuse_storage_map"]
    assert storage["suite_catalog"] == "public.lf_test_suites"
    assert storage["case_execution"] == "public.lf_test_runs"
    assert storage["metric_assertions"] == "public.lf_test_assertion_results"


def test_runners_are_syntax_valid_and_have_no_network_client_imports():
    for name in ["run_local_performance_baseline.py", "compare_performance_baselines.py"]:
        source = (HERE / name).read_text(encoding="utf-8")
        ast.parse(source, filename=name)
        assert "urllib" not in source
        assert "requests" not in source
        assert "httpx" not in source
