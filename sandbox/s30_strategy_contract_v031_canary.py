#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

MODULE = Path("gobernanza/judges/validate_strategy_contract.py")
spec = importlib.util.spec_from_file_location("validate_strategy_contract", MODULE)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_S30_VALIDATOR_MODULE_LOAD")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

EXTENSIONS = {
    "GOVERNANCE": {
        "authority_model": "ACT-0001",
        "ownership_boundaries": ["S30 owns strategy creation governance"],
        "lifecycle_or_policy_impact": "candidate only",
        "conflict_and_waiver_handling": "fail closed",
        "next_gate_or_handoff": "quality",
    },
    "TECHNICAL_OPERATIONAL": {
        "runtime_or_system_boundary": "sandbox",
        "failure_modes_and_first_bad_hop": ["timeout", "partial failure"],
        "reliability_test_plan": ["idempotency", "retry"],
        "performance_or_resource_metrics_or_explicit_na": {"latency": "measured"},
        "rollback_or_recovery": {"route": "A_ORIGINAL"},
        "next_gate_or_handoff": "quality",
    },
    "PRODUCT": {
        "target_user_or_state": "operator",
        "selected_decision": "candidate",
        "rejected_alternatives": ["freeform"],
        "tradeoffs": ["strictness vs flexibility"],
        "value_metric_or_success_proxy": {"false_close": 0},
        "observable_acceptance_criteria": ["contract validates"],
        "next_gate_or_handoff": "quality",
    },
    "RESEARCH_BENCHMARK": {
        "research_questions_or_hypotheses": ["does the contract generalize"],
        "methodology": "holdout cases",
        "sample_dataset_or_case_families": ["governance", "product"],
        "evaluation_criteria": ["quality", "depth"],
        "leakage_and_bias_controls": ["unseen cases"],
        "next_gate_or_handoff": "quality",
    },
    "MIGRATION_DEPLOYMENT": {
        "source_target_versions": {"source": "v1", "target": "v2"},
        "parity_contract": {"required": True},
        "rollout_or_cutover_plan": ["canary"],
        "rollback_plan": ["revert"],
        "smoke_ci_and_readback": ["exact-head"],
        "production_boundary": "no production",
        "next_gate_or_handoff": "quality",
    },
    "CANARY_VALIDATION": {
        "proof_target": "strategy factory",
        "positive_case": "valid candidate",
        "negative_cases": ["missing field"],
        "exact_evidence_boundary": "R3",
        "cleanup_or_demotion_plan": "demote",
        "next_gate_or_handoff": "quality",
    },
}


def base(archetype: str, stage_count: int = 1) -> dict:
    stages = []
    for i in range(stage_count):
        code = f"S{i}"
        stages.append({
            "stage_code": code,
            "objective_or_purpose": f"stage {i}",
            "status": "CURRENT" if i == 0 else "PENDING",
            "entry_conditions": ["ready"],
            "actions_or_scope": ["run"],
            "tests": ["T"],
            "evidence_required": ["E"],
            "exit_gate": "PASS",
            "conclusion_ref": f"C{i}",
        })
    return {
        "problem_statement": "p",
        "objective": "o",
        "scope": ["s"],
        "non_goals": ["n"],
        "baseline": {"b": 1},
        "authorities": ["ACT-0001"],
        "dependencies": [{"id": "S30"}],
        "applicable_policies": [{"code": "POL"}],
        "stages": stages,
        "gates": ["G"],
        "tests": [{"id": "T"}],
        "metrics": {"m": 1},
        "risks": [{"id": "R"}],
        "evidence_contract": {"ceiling": "R3"},
        "rollback_or_recovery": {"routes": ["A"]},
        "execution_frontier": {
            "current_stage": "S0",
            "current_action": "run",
            "safe_parallel_work": [],
            "blockers": [],
        },
        "stage_conclusions": [],
        "invalidation_triggers": ["x"],
        "change_log": [{"version": "v0.1"}],
        "closure_criteria": ["c"],
        "strategy_archetype": archetype,
        "type_extension": copy.deepcopy(EXTENSIONS[archetype]),
        "next_gate_or_handoff": "quality",
    }


def conclusion(stage_code: str, conclusion_id: str) -> dict:
    return {
        "conclusion_id": conclusion_id,
        "stage_code": stage_code,
        "status": "PASS",
        "conclusion": "ok",
        "claim_ceiling": "R3",
        "open_risks": [],
        "carry_forward": [],
        "invalidation_triggers": ["x"],
    }


def expect(name: str, payload: dict, mode: str, valid: bool, code: str | None = None) -> dict:
    result = validator.validate(payload, mode)
    ok = result["valid"] == valid and (code is None or code in result["blocking_codes"])
    return {
        "name": name,
        "ok": ok,
        "mode": mode,
        "expected_valid": valid,
        "blocking_codes": result["blocking_codes"],
        "results_sha256": result["results_sha256"],
    }


results = []
builtin = validator.self_test()
results.append({"name": "builtin_self_test", "ok": bool(builtin["all_pass"]), "case_count": builtin["case_count"]})

for archetype in EXTENSIONS:
    payload = base(archetype)
    results.append(expect(f"positive_{archetype}", payload, "prewrite", True))
    missing = copy.deepcopy(payload)
    first_required = validator.ARCHETYPE_REQUIRED_FIELDS[archetype][0]
    missing["type_extension"].pop(first_required)
    results.append(expect(f"missing_required_{archetype}", missing, "prewrite", False, "MISSING_REQUIRED_TYPE_EXTENSION_FIELD"))

payload = base("CANARY_VALIDATION")
payload["stages"][0].pop("tests")
results.append(expect("missing_stage_field", payload, "prewrite", False, "INCOMPLETE_STAGE_SCHEMA"))

payload = base("CANARY_VALIDATION")
payload["stage_conclusions"] = [conclusion("S0", "C0"), conclusion("S0", "C0B")]
results.append(expect("duplicate_current_conclusion", payload, "prewrite", False, "DUPLICATE_CURRENT_STAGE_CONCLUSION"))

payload = base("CANARY_VALIDATION")
payload["stage_conclusions"] = [conclusion("S0", "WRONG")]
results.append(expect("conclusion_ref_mismatch", payload, "prewrite", False, "STAGE_CONCLUSION_REF_MISMATCH"))

payload = base("CANARY_VALIDATION")
payload["strategy_archetype"] = "UNKNOWN"
results.append(expect("unknown_archetype", payload, "prewrite", False, "UNKNOWN_STRATEGY_TYPE_WITHOUT_EXTENSION"))

payload = base("CANARY_VALIDATION")
payload["strategy_archetype"] = "CUSTOM"
payload["type_extension"] = {}
results.append(expect("custom_without_schema_ref", payload, "prewrite", False, "CUSTOM_EXTENSION_SCHEMA_REF_MISSING"))

payload = base("CANARY_VALIDATION")
payload.pop("next_gate_or_handoff")
payload["type_extension"].pop("next_gate_or_handoff")
results.append(expect("missing_handoff", payload, "prewrite", False, "MISSING_NEXT_GATE_OR_HANDOFF"))

payload = base("CANARY_VALIDATION")
payload["execution_frontier"] = {"state": "CLOSED", "current_stage": "S0", "current_action": "NONE", "safe_parallel_work": [], "blockers": []}
results.append(expect("close_missing_conclusion", payload, "close", False, "MISSING_STAGE_CONCLUSION_AT_CLOSE"))

payload = base("CANARY_VALIDATION")
payload["stage_conclusions"] = [conclusion("S0", "C0")]
payload["execution_frontier"] = {"state": "CLOSED", "current_stage": "S0", "current_action": "NONE", "safe_parallel_work": [], "blockers": []}
results.append(expect("positive_close", payload, "close", True))

# Critical regression for Product/Quality finding QA-03/PRD-03:
# a CLOSED frontier may not point to an earlier stage when a later stage exists.
payload = base("CANARY_VALIDATION", stage_count=2)
payload["stage_conclusions"] = [conclusion("S0", "C0"), conclusion("S1", "C1")]
payload["execution_frontier"] = {"state": "CLOSED", "current_stage": "S0", "current_action": "NONE", "safe_parallel_work": [], "blockers": []}
results.append(expect("close_frontier_points_to_nonterminal_stage", payload, "close", False, "STALE_EXECUTION_FRONTIER"))

failed = [r for r in results if not r["ok"]]
summary = {
    "validator_version": validator.VERSION,
    "total_cases": len(results),
    "passed": len(results) - len(failed),
    "failed": len(failed),
    "all_pass": not failed,
    "results": results,
}
print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
if failed:
    raise SystemExit("FAIL_S30_STRATEGY_CONTRACT_V031_CANARY")
print("PASS_S30_STRATEGY_CONTRACT_V031_CANARY")
