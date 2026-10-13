"""Frozen 24-case selector policy diagnostic; NOT an expert task benchmark.

Usage (clean Git checkout):
  python sandbox/lf_contract_gate_test/transversal_assets/capability_selector/test_profile_math_selector_policy_24_v1.py
  python .../test_profile_math_selector_policy_24_v1.py --baseline-ref <exact-pr1947-head>

The optional baseline loads the original V3 algorithm from Git by exact supplied
ref, instead of copying or reimplementing it. Outcomes are method choices only.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import types
from pathlib import Path

from capability_selector_v3 import compose_capabilities_v3

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REG_PATH = HERE.parent / "method_pack_registry" / "method_pack_registry_v2.json"
REG = json.loads(REG_PATH.read_text(encoding="utf-8"))
MATH = frozenset(REG["math_extension"]["method_ids"])


def verified(value):
    return {"value": value, "verification_state": "VERIFIED", "evidence_refs": ["fixture://typed-value"]}


def conditions():
    # Synthetic, internally consistent conditions. NOT verified provider proofs.
    return {p["key"]: verified(p["expected"]) for m in REG["methods"]
            for p in m.get("precondition_contract", [])}


def catalog():
    return [{"capability_code": "CURRENTNESS_AUTHORITY", "signal_type": "risk",
             "accepted_values": ["LOW"], "rank": 1, "state": "AVAILABLE"}]


def verified_regression(delta, critical, state="VERIFIED"):
    return {"verification_state": state, "evidence_refs": ["fixture://historical-report"],
            "paired_quality_delta": delta, "critical_regressions": critical,
            "independent_holdout_verified": True}


MIX = {"complexity": "HIGH", "causal_requirement": "HIGH", "repeated_pattern": True,
       "evidence_paths": "MULTIPLE_INDEPENDENT", "optimization_need": "REQUIRED",
       "profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"]}

# Frozen behavioral oracle: these labels express explicit expected selection
# requirements, not measured answer quality, user production cases or expertise.
CASES = [
    ("C01", {"causal_requirement": "HIGH"}, {}, "CAUSAL_GRAPH_ANALYSIS", "SHADOW_RECOMMENDATIONS_READY"),
    ("C02", {"repeated_pattern": True}, {}, "OCHIAI_SUSPICIOUSNESS", "SHADOW_RECOMMENDATIONS_READY"),
    ("C03", {"evidence_paths": "MULTIPLE_INDEPENDENT"}, {}, "RECIPROCAL_RANK_FUSION", "SHADOW_RECOMMENDATIONS_READY"),
    ("C04", {"profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"]}, {}, "DELTA_DEBUGGING", "SHADOW_RECOMMENDATIONS_READY"),
    ("C05", {"optimization_need": "REQUIRED"}, {}, "MCNEMAR_AND_CONFIDENCE_INTERVALS", "SHADOW_RECOMMENDATIONS_READY"),
    ("C06", {"complexity": "LOW"}, {}, None, "NO_MATHEMATICAL_METHOD_NEEDED"),
    ("C07", {"novelty": "HIGH"}, {}, None, "NO_MATHEMATICAL_METHOD_NEEDED"),
    ("C08", {"risk": "HIGH"}, {}, None, "NO_MATHEMATICAL_METHOD_NEEDED"),
    ("C09", {"causal_requirement": "HIGH"}, {"material_graph_bound": None}, None, "EVIDENCE_REQUIRED"),
    ("C10", {"repeated_pattern": True}, {"passing_negative_controls_exist": None}, None, "EVIDENCE_REQUIRED"),
    ("C11", {"evidence_paths": "MULTIPLE_INDEPENDENT"}, {"rank_source_currentness_verified": None}, None, "EVIDENCE_REQUIRED"),
    ("C12", {"profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"]}, {"safe_deterministic_replay_exists": None}, None, "EVIDENCE_REQUIRED"),
    ("C13", {"optimization_need": "REQUIRED"}, {"blind_independent_evaluator_exists": None}, None, "EVIDENCE_REQUIRED"),
    ("C14", {"causal_requirement": "HIGH", "budget": {"max_shadow_method_cost_points": 0}}, {}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
    ("C15", {"repeated_pattern": True, "method_effectiveness_observations": {"OCHIAI_SUSPICIOUSNESS": verified_regression(.7, 1)}}, {}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
    ("C16", {"repeated_pattern": True, "method_effectiveness_observations": {"OCHIAI_SUSPICIOUSNESS": verified_regression(-.1, 0)}}, {}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
    ("C17", {"causal_requirement": "HIGH", "blocked_methods": ["CAUSAL_GRAPH_ANALYSIS"]}, {}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
    ("C18", {"causal_requirement": "HIGH", "budget": {"max_shadow_method_trials": 0}}, {}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
    ("C19", MIX, {}, "DELTA_DEBUGGING", "SHADOW_RECOMMENDATIONS_READY"),
    ("C20", {**MIX, "method_effectiveness_observations": {"MCNEMAR_AND_CONFIDENCE_INTERVALS": verified_regression(.99, 0)}}, {}, "DELTA_DEBUGGING", "SHADOW_RECOMMENDATIONS_READY"),
    ("C21", {"complexity": "HIGH"}, {"failure_predicate_reproduced": False}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
    ("C22", {"repeated_pattern": True, "method_effectiveness_observations": {"OCHIAI_SUSPICIOUSNESS": verified_regression(-1, 100, "UNKNOWN")}}, {}, "OCHIAI_SUSPICIOUSNESS", "SHADOW_RECOMMENDATIONS_READY"),
    ("C23", {"repeated_pattern": True, "budget": {"max_shadow_method_cost_points": 1}}, {}, "OCHIAI_SUSPICIOUSNESS", "SHADOW_RECOMMENDATIONS_READY"),
    ("C24", {"profile_gaps": ["MINIMIZE_REPRODUCIBLE_FAILURE"], "budget": {"max_shadow_method_cost_points": 1}}, {}, None, "NO_ELIGIBLE_MATHEMATICAL_METHOD"),
]


def original_v3_from_git(ref: str):
    if not isinstance(ref, str) or not ref or ref.startswith("-"):
        raise ValueError("BASELINE_REF_REQUIRED")
    path = "sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v3.py"
    fetched = subprocess.run(["git", "-C", str(ROOT), "show", ref + ":" + path],
                             check=True, capture_output=True, text=True, timeout=20)
    # Require same V2 dependency to avoid a misleading mixed-source comparison.
    dep = "sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v2.py"
    dep_data = subprocess.run(["git", "-C", str(ROOT), "show", ref + ":" + dep],
                              check=True, capture_output=True, text=True, timeout=20)
    if dep_data.stdout != (HERE / "capability_selector_v2.py").read_text(encoding="utf-8"):
        raise ValueError("BASELINE_V2_DEPENDENCY_DRIFT")
    original = types.ModuleType("profile_baseline_v3_exact_source")
    exec(compile(fetched.stdout, "exact_baseline_v3.py", "exec"), original.__dict__)
    return original.compose_capabilities_v3


def run(baseline_ref=None):
    assert len(CASES) == 24 and len(MATH) == 5
    baseline_compose = original_v3_from_git(baseline_ref) if baseline_ref else None
    baseline_correct = current_correct = 0
    for code, context, omissions, expected, expected_status in CASES:
        pre = conditions()
        for key, val in omissions.items():
            pre[key] = verified(val) if val is not None else {
                "value": None, "verification_state": "UNKNOWN", "evidence_refs": []}
        result = compose_capabilities_v3(context, catalog(),
                                         {"fallback_capabilities": []}, REG, pre)
        math = result["mathematical_method_selection"]
        chosen = [x["method_id"] for x in math["recommended_trials"]]
        actual = chosen[0] if chosen else None
        assert actual == expected, (code, expected, actual, math)
        assert math["status"] == expected_status, (code, expected_status, math)
        assert all(x.get("method_id") not in MATH for x in result["selected_methods"]), code
        assert result["execution_authorized"] is False and math["execution_authorized"] is False
        current_correct += 1
        if baseline_compose:
            baseline_reg = json.loads(subprocess.run(
                ["git", "-C", str(ROOT), "show",
                 baseline_ref + ":sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v2.json"],
                check=True, capture_output=True, text=True, timeout=20).stdout)
            base = baseline_compose(context, catalog(), {"fallback_capabilities": []},
                                    baseline_reg, pre)
            # Baseline V3 has no math output lane; this only measures declared
            # selection-policy coverage, NOT superiority at solving domain tasks.
            assert "mathematical_method_selection" not in base, code
            baseline_correct += int(expected is None)
    assert current_correct == len(CASES)
    print(json.dumps({
        "schema": "PROFILE_MATH_SELECTOR_POLICY_DIAGNOSTIC_V1",
        "status": "PASS_POLICY_FIXTURES_ONLY",
        "case_count": len(CASES),
        "candidate_policy_pass": current_correct,
        "baseline_policy_pass": baseline_correct if baseline_ref else None,
        "baseline_source_ref": baseline_ref,
        "all_math_execution_disabled": True,
        "expert_task_uplift_measured": False,
        "independent_model_judge_executed": False,
        "method_admission_authorized": False,
    }, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-ref", default=None)
    run(parser.parse_args().baseline_ref)
