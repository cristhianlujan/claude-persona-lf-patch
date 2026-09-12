from __future__ import annotations

from collections import Counter
import json
from pathlib import Path

from validate_missing_objectives_plan import effective_status, projected_dimensions

ROOT = Path(__file__).resolve().parent
INVENTORY = ROOT / "coverage_inventory.json"
MATRIX_CONTRACT = ROOT / "matrix_contract.json"
PLAN = ROOT / "missing_objectives_plan.json"
ADDENDUM = ROOT / "performance_applicability_addendum.json"
PREBUILD_CONTRACT = ROOT / "w0_prebuild_contract.json"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def effective_cases(plan: dict, addendum: dict) -> list[dict]:
    cases = [
        {**case, "dimensions_to_close": list(case["dimensions_to_close"])}
        for case in plan["cases"]
    ]
    by_objective = {case["objective_id"]: case for case in cases}
    if len(by_objective) != len(cases):
        raise AssertionError("BASE_PLAN_DUPLICATE_OBJECTIVE")

    for augmentation in addendum["augment_existing_cases"]:
        oid = augmentation["objective_id"]
        if oid not in by_objective:
            raise AssertionError(f"AUGMENT_TARGET_MISSING:{oid}")
        case = by_objective[oid]
        for dimension in augmentation["add_dimensions"]:
            if dimension in case["dimensions_to_close"]:
                raise AssertionError(f"AUGMENT_DIMENSION_ALREADY_PRESENT:{oid}:{dimension}")
            case["dimensions_to_close"].append(dimension)

    for case in addendum["new_cases"]:
        oid = case["objective_id"]
        if oid in by_objective:
            raise AssertionError(f"ADDENDUM_NEW_CASE_ALREADY_IN_BASE_PLAN:{oid}")
        copied = {**case, "dimensions_to_close": list(case["dimensions_to_close"])}
        cases.append(copied)
        by_objective[oid] = copied

    return sorted(cases, key=lambda item: item["objective_id"])


def select_executor(case: dict, prebuild: dict) -> str:
    rules = prebuild["executor_rules"]
    dimensions = set(case["dimensions_to_close"])
    if dimensions == {"performance"}:
        return rules["performance_rebind_only"]

    wave = case["final_wave"]
    closure_mode = case["closure_mode"]
    if wave == "W1_FINAL_DETERMINISTIC":
        return rules["w1_default"]
    if wave == "W2_FINAL_MODEL_MATERIALIZATION":
        return rules["w2_default"]
    if wave == "W3_FINAL_STABILITY_AND_INDEPENDENT":
        if "INDEPENDENT_REVIEW" in closure_mode:
            return rules["w3_independent_review"]
        if "STOCHASTIC" in closure_mode:
            return rules["w3_repeated_stochastic"]
        return rules["w3_default"]
    raise AssertionError(f"UNKNOWN_FINAL_WAVE:{case['case_id']}:{wave}")


def build_recipes() -> dict:
    inventory = _read(INVENTORY)
    matrix_contract = _read(MATRIX_CONTRACT)
    plan = _read(PLAN)
    addendum = _read(ADDENDUM)
    prebuild = _read(PREBUILD_CONTRACT)

    objectives: dict[str, dict] = {}
    family_by_objective: dict[str, str] = {}
    effective: dict[str, str] = {}
    expected_dimensions: dict[str, set[str]] = {}
    for family in inventory["families"]:
        for objective in family["objectives"]:
            oid = objective["objective_id"]
            objectives[oid] = objective
            family_by_objective[oid] = family["family_id"]
            effective[oid] = effective_status(objective, matrix_contract)
            projected = projected_dimensions(objective, matrix_contract)
            expected_dimensions[oid] = {
                name for name, status in projected.items()
                if status in {"PARTIAL", "PENDING"}
            }

    gaps = {oid for oid, status in effective.items() if status != "COVERED"}
    cases = effective_cases(plan, addendum)
    if {case["objective_id"] for case in cases} != gaps:
        raise AssertionError("EFFECTIVE_CASE_SET_DOES_NOT_MATCH_GAPS")

    bindings = prebuild["family_bindings"]
    recipes: list[dict] = []
    for case in cases:
        oid = case["objective_id"]
        family = case["family"]
        if family != family_by_objective[oid]:
            raise AssertionError(f"FAMILY_MISMATCH:{case['case_id']}")
        if case["baseline"] != effective[oid]:
            raise AssertionError(f"BASELINE_MISMATCH:{case['case_id']}")
        if set(case["dimensions_to_close"]) != expected_dimensions[oid]:
            raise AssertionError(f"DIMENSION_CLOSURE_MISMATCH:{case['case_id']}")
        if family not in bindings:
            raise AssertionError(f"MISSING_FAMILY_BINDING:{family}")

        executor = select_executor(case, prebuild)
        closure_mode = case["closure_mode"]
        final_wave = case["final_wave"]
        performance_only = set(case["dimensions_to_close"]) == {"performance"}
        requires_model = (
            final_wave == "W2_FINAL_MODEL_MATERIALIZATION"
            or "INDEPENDENT_REVIEW" in closure_mode
            or "STOCHASTIC" in closure_mode
            or closure_mode == "UNSEEN_REAL_E2E_HOLDOUT"
        )
        requires_independent_review = (
            "INDEPENDENT_REVIEW" in closure_mode
            or closure_mode == "UNSEEN_REAL_E2E_HOLDOUT"
        )
        requires_repetition = "STOCHASTIC" in closure_mode
        dimensions = list(case["dimensions_to_close"])

        recipe = {
            "case_id": case["case_id"],
            "objective_id": oid,
            "family": family,
            "baseline": case["baseline"],
            "source_authority_commit": prebuild["source_authority_commit"],
            "prebuild_wave": case["prebuild_wave"],
            "final_wave": final_wave,
            "executor": executor,
            "target_component": bindings[family]["target_component"],
            "oracle": bindings[family]["oracle"],
            "closure_mode": closure_mode,
            "failure_mode": case["failure_mode"],
            "expected": case["expected"],
            "learning": case["learning"],
            "dimensions_to_close": dimensions,
            "unseen_holdout": case["unseen_holdout"],
            "performance_only_rebind": performance_only,
            "requires_model": requires_model,
            "requires_independent_review": requires_independent_review,
            "requires_repetition": requires_repetition,
            "performance_metrics": (
                list(prebuild["performance_receipt_fields_when_applicable"])
                if "performance" in dimensions else []
            ),
            "execution_enabled": False,
            "final_candidate_sha": None,
            "independent_case_credit": not performance_only,
        }
        recipes.append(recipe)

    baseline_counts = Counter(effective.values())
    summary = {
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_W0_EXECUTION_RECIPES_V1",
        "status": "PREBUILD_READY_FINAL_EXECUTION_DISABLED",
        "effective_baseline": dict(baseline_counts),
        "recipe_count": len(recipes),
        "performance_rebind_only": sum(r["performance_only_rebind"] for r in recipes),
        "semantic_gap_cases": sum(not r["performance_only_rebind"] for r in recipes),
        "designated_unseen_holdouts": sum(r["unseen_holdout"] for r in recipes),
        "model_required_final_cases": sum(r["requires_model"] for r in recipes),
        "independent_review_final_cases": sum(r["requires_independent_review"] for r in recipes),
        "repeated_stability_final_cases": sum(r["requires_repetition"] for r in recipes),
        "execution_enabled_count": sum(r["execution_enabled"] for r in recipes),
        "recipes": recipes,
        "claim_ceiling": prebuild["claim_ceiling"],
    }
    return summary


def main() -> None:
    print(json.dumps(build_recipes(), sort_keys=True))


if __name__ == "__main__":
    main()
