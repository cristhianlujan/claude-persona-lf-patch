from __future__ import annotations

from collections import Counter, defaultdict
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MATRIX_DIR = ROOT / "s26_family_objective_matrix_v3"
BUILDER = MATRIX_DIR / "build_w0_execution_recipes.py"
CONTRACT = MATRIX_DIR / "w0_prebuild_contract.json"


def load_builder():
    spec = importlib.util.spec_from_file_location("s26_w0_recipe_builder", BUILDER)
    assert spec and spec.loader, "W0_BUILDER_IMPORT_SPEC_MISSING"
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.path.insert(0, str(MATRIX_DIR))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.pop(0)
    return module


def main() -> None:
    assert BUILDER.is_file(), "W0_BUILDER_MISSING"
    assert CONTRACT.is_file(), "W0_PREBUILD_CONTRACT_MISSING"
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    builder = load_builder()
    result = builder.build_recipes()
    recipes = result["recipes"]

    expected = contract["expected_effective_projection"]
    assert result["status"] == "PREBUILD_READY_FINAL_EXECUTION_DISABLED"
    assert result["claim_ceiling"] == "W0_PREBUILD_READY_NOT_EXECUTED_NOT_CERTIFIED_NOT_GATE_G_NOT_GOLDEN"
    assert result["recipe_count"] == expected["gap_objectives"] == 33
    assert result["performance_rebind_only"] == expected["performance_rebind_only"] == 7
    assert result["semantic_gap_cases"] == expected["semantic_gap_cases"] == 26
    assert result["designated_unseen_holdouts"] == expected["designated_unseen_holdouts"] == 10
    assert result["execution_enabled_count"] == 0
    assert result["effective_baseline"] == {
        "COVERED": 17,
        "NEW_CASE_REQUIRED": 9,
        "NOT_DEMONSTRATED": 8,
        "PARTIAL": 16,
    }

    case_ids = [recipe["case_id"] for recipe in recipes]
    objective_ids = [recipe["objective_id"] for recipe in recipes]
    assert len(case_ids) == len(set(case_ids)) == 33, "W0_DUPLICATE_CASE_ID"
    assert len(objective_ids) == len(set(objective_ids)) == 33, "W0_DUPLICATE_OBJECTIVE_ID"

    holdouts: defaultdict[str, list[str]] = defaultdict(list)
    wave_counts = Counter()
    executor_counts = Counter()
    family_counts = Counter()
    for recipe in recipes:
        assert recipe["execution_enabled"] is False, f"W0_EXECUTION_ENABLED:{recipe['case_id']}"
        assert recipe["final_candidate_sha"] is None, f"W0_FINAL_CANDIDATE_PREBOUND:{recipe['case_id']}"
        assert recipe["source_authority_commit"] == "48916fd36bcaff8eadd60944848e81adbea55c54"
        assert recipe["prebuild_wave"] == "W0_PREBUILD_NOW"
        assert recipe["final_wave"] in {
            "W1_FINAL_DETERMINISTIC",
            "W2_FINAL_MODEL_MATERIALIZATION",
            "W3_FINAL_STABILITY_AND_INDEPENDENT",
        }
        assert recipe["target_component"].strip()
        assert recipe["oracle"].strip()
        assert recipe["failure_mode"].strip()
        assert recipe["expected"].strip()
        assert recipe["learning"].strip()
        assert recipe["dimensions_to_close"]

        wave_counts[recipe["final_wave"]] += 1
        executor_counts[recipe["executor"]] += 1
        family_counts[recipe["family"]] += 1

        if recipe["unseen_holdout"]:
            holdouts[recipe["family"]].append(recipe["case_id"])

        if recipe["performance_only_rebind"]:
            assert recipe["dimensions_to_close"] == ["performance"]
            assert recipe["executor"] == "PERFORMANCE_REPLAY_BINDER"
            assert recipe["independent_case_credit"] is False
        else:
            assert recipe["independent_case_credit"] is True

        if "performance" in recipe["dimensions_to_close"]:
            assert recipe["performance_metrics"] == [
                "latency_ms",
                "model_calls",
                "context_or_token_proxy",
                "retries",
            ]
        else:
            assert recipe["performance_metrics"] == []

        if recipe["final_wave"] == "W1_FINAL_DETERMINISTIC" and not recipe["performance_only_rebind"]:
            assert recipe["executor"] == "DETERMINISTIC_CASE_HARNESS"
            assert recipe["requires_model"] is False

        if recipe["final_wave"] == "W2_FINAL_MODEL_MATERIALIZATION" and not recipe["performance_only_rebind"]:
            assert recipe["executor"] == "MODEL_MATERIALIZATION_CASE_HARNESS"
            assert recipe["requires_model"] is True

        if recipe["requires_independent_review"]:
            assert recipe["final_wave"] == "W3_FINAL_STABILITY_AND_INDEPENDENT"
            assert recipe["requires_model"] is True

        if recipe["requires_repetition"]:
            assert recipe["executor"] == "REPEATED_STABILITY_HARNESS"
            assert recipe["requires_model"] is True

    assert len(family_counts) == 10, f"W0_FAMILY_COVERAGE:{dict(family_counts)}"
    assert set(holdouts) == set(contract["family_bindings"]), f"W0_HOLDOUT_FAMILY_SET:{sorted(holdouts)}"
    assert all(len(ids) == 1 for ids in holdouts.values()), f"W0_HOLDOUT_CARDINALITY:{dict(holdouts)}"
    assert sum(wave_counts.values()) == 33
    assert executor_counts["PERFORMANCE_REPLAY_BINDER"] == 7

    assert contract["execution_policy"] == {
        "w0_may_execute_final_cases": False,
        "w0_may_call_model": False,
        "w0_may_call_independent_reviewer": False,
        "w0_may_write_runtime_or_database": False,
        "w0_may_promote_gate_g_or_golden": False,
        "final_candidate_sha_required_for_w1_w2_w3": True,
        "objective_receipt_required": True,
        "shared_execution_does_not_create_independent_case_credit": True,
    }
    assert contract["final_execution_prerequisites"] == [
        "PR_682_INTEGRATED",
        "PR_681_INTEGRATED_AND_MIGRATION_APPLIED_WITH_READBACK",
        "FINAL_S26_RUNTIME_AFFECTING_CANDIDATE_STABLE",
    ]

    print(json.dumps({
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_W0_PREBUILD_VALIDATION_V1",
        "result": "PASS",
        "recipes": len(recipes),
        "families": len(family_counts),
        "holdouts": sum(len(ids) for ids in holdouts.values()),
        "performance_rebind_only": result["performance_rebind_only"],
        "semantic_gap_cases": result["semantic_gap_cases"],
        "final_wave_counts": dict(wave_counts),
        "executor_counts": dict(executor_counts),
        "model_calls": 0,
        "runtime_writes": 0,
        "system_certified": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
