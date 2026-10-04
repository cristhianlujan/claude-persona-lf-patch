#!/usr/bin/env python3
"""M8.0 source-only contract tests. No runtime/tuning behavior is implemented here."""
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = ROOT / "docs" / "ig_refactor" / "performance_contract_v1.json"
T_PERF_DIR = ROOT / "sandbox" / "lf_contract_gate_test" / "transversal_assets" / "performance"
sys.path.insert(0, str(T_PERF_DIR))
from timeout_phase_budget_policy_v1 import evaluate_timeout_request  # noqa: E402

CONTRACT = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))


def contract_candidate_passes(*, validator_executed: bool = True, assurance_ok: bool = True,
                              stale_cache: bool = False, mean_improved: bool = True,
                              p90_ms: int = 90000, total_ms: int = 110000,
                              all_applicable_q_gates: bool = True) -> bool:
    """Test-only projection of declarative M8.0 invalidation rules."""
    p = CONTRACT["performance"]
    return all((
        validator_executed,
        assurance_ok,
        not stale_cache,
        mean_improved,
        p90_ms <= p["p90_target_ms"],
        total_ms <= p["total_screen_budget_ms"],
        all_applicable_q_gates,
    ))


def test_contract_shape_and_budget():
    p = CONTRACT["performance"]
    assert sum(p["phase_budgets_ms"].values()) == p["total_screen_budget_ms"] == 120000
    assert p["edge_limit_ms"] == 150000
    assert p["edge_margin_ms"] == 30000
    assert p["edge_margin_pct"] == 20
    assert p["p90_target_ms"] == 100000
    assert p["total_screen_budget_ms"] < p["edge_limit_ms"]
    assert CONTRACT["scope_guards"] == {
        "runtime_change": False,
        "timeout_tuning": False,
        "production_activation": False,
        "new_performance_engine": False,
    }


def test_all_q_classes_and_validator_are_mandatory():
    q = CONTRACT["quality"]
    assert q["validator_required"] is True
    assert q["required_q_classes"] == [f"Q{i}" for i in range(9)]
    assert q["current_suite_baseline_cases"] == 168
    assert q["m7_3_negative_baseline_cases"] == 91


def test_negative_omit_validator_fails():
    assert not contract_candidate_passes(validator_executed=False)


def test_negative_raise_timeout_without_diagnosis_fails_via_t_perf():
    source_sha = "a" * 64
    policy = {
        "schema_version": "lf-timeout-phase-budget-policy/v1",
        "phase_budgets_ms": CONTRACT["performance"]["phase_budgets_ms"],
        "min_benchmark_samples": 3,
    }
    decision = evaluate_timeout_request(
        phase="VALIDATOR",
        requested_timeout_ms=60000,
        policy=policy,
        exact_source_sha256=source_sha,
        benchmark_receipt=None,
    )
    assert decision["decision"] == "BLOCKED_BLIND_TIMEOUT_EXTENSION"
    assert decision["mutates_timeout"] is False


def test_negative_stale_cache_fails():
    assert not contract_candidate_passes(stale_cache=True)


def test_negative_mean_better_but_p90_worse_fails():
    assert not contract_candidate_passes(mean_improved=True, p90_ms=100001)


def test_negative_performance_pass_assurance_fail_fails():
    assert not contract_candidate_passes(assurance_ok=False, p90_ms=90000, total_ms=110000)


def test_declared_negative_matrix_is_complete():
    expected = {
        "OMIT_VALIDATOR",
        "RAISE_TIMEOUT_WITHOUT_DIAGNOSIS",
        "REUSE_STALE_CACHE",
        "MEAN_BETTER_P90_WORSE",
        "PERFORMANCE_PASS_ASSURANCE_FAIL",
    }
    observed = {x["case"] for x in CONTRACT["negative_tests"] if x["expected"] == "FAIL"}
    assert observed == expected
