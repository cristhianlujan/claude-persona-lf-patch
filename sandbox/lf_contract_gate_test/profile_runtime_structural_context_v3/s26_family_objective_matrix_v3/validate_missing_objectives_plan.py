from __future__ import annotations

from collections import Counter, defaultdict
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
INVENTORY = ROOT / "coverage_inventory.json"
CONTRACT = ROOT / "matrix_contract.json"
PLAN = ROOT / "missing_objectives_plan.json"
ADDENDUM = ROOT / "performance_applicability_addendum.json"


def projected_dimensions(objective: dict, contract: dict) -> dict[str, str]:
    dims = dict(objective["dimensions"])
    oid = objective["objective_id"]
    allowed_na = set(contract["na_policy"]["allowed_dimensions"])
    policy = contract["na_policy"].get("performance_na_reclassification", {}).get(oid)
    if policy is not None:
        assert dims.get("performance") == "N_A", f"RECLASSIFICATION_TARGET_NOT_NA:{oid}:{dims.get('performance')}"
        projected = policy["effective_status"]
        assert projected in {"COVERED", "PENDING"}, f"BAD_PERFORMANCE_RECLASSIFICATION:{oid}:{projected}"
        required_refs = set(policy.get("required_evidence_refs", []))
        actual_refs = set(objective.get("evidence_refs", []))
        assert required_refs <= actual_refs, f"PERFORMANCE_RECLASSIFICATION_EVIDENCE_MISSING:{oid}:{sorted(required_refs - actual_refs)}"
        dims["performance"] = projected
    invalid_na = [name for name, value in dims.items() if value == "N_A" and name not in allowed_na]
    assert not invalid_na, f"INVALID_NA:{oid}:{invalid_na}"
    return dims


def effective_status(objective: dict, contract: dict) -> str:
    declared = objective["status"]
    dims = projected_dimensions(objective, contract)
    pending = [name for name, value in dims.items() if value == "PENDING"]
    partial = [name for name, value in dims.items() if value == "PARTIAL"]
    if declared == "NEW_CASE_REQUIRED":
        return "NEW_CASE_REQUIRED"
    if pending:
        return "NOT_DEMONSTRATED" if declared == "NOT_DEMONSTRATED" else "PARTIAL"
    if partial:
        return "PARTIAL"
    return "COVERED"


def main() -> None:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    addendum = json.loads(ADDENDUM.read_text(encoding="utf-8"))

    assert addendum["schema"] == "S26_FAMILY_OBJECTIVE_MATRIX_V3_PERFORMANCE_APPLICABILITY_ADDENDUM_V1"
    assert plan["objectives_to_close"] == len(plan["cases"]) == 30, "BASE_PLAN_DRIFT"

    objectives: dict[str, dict] = {}
    family_by_objective: dict[str, str] = {}
    effective: dict[str, str] = {}
    expected_dimensions: dict[str, set[str]] = {}
    family_ids = {family["family_id"] for family in inventory["families"]}

    for family in inventory["families"]:
        for objective in family["objectives"]:
            oid = objective["objective_id"]
            objectives[oid] = objective
            family_by_objective[oid] = family["family_id"]
            effective[oid] = effective_status(objective, contract)
            projected = projected_dimensions(objective, contract)
            expected_dimensions[oid] = {
                name for name, status in projected.items()
                if status in {"PARTIAL", "PENDING"}
            }

    gaps = {oid for oid, status in effective.items() if status != "COVERED"}
    assert len(gaps) == addendum["projected_objectives_to_close"] == 33, (len(gaps), addendum["projected_objectives_to_close"])

    cases = [
        {**case, "dimensions_to_close": list(case["dimensions_to_close"])}
        for case in plan["cases"]
    ]
    base_case_by_objective = {case["objective_id"]: case for case in cases}
    assert len(base_case_by_objective) == len(cases), "BASE_PLAN_DUPLICATE_OBJECTIVE"

    base_rebind_labeled_cases = sum("REBIND" in case["closure_mode"] for case in cases)
    base_performance_only_rebind_cases = sum(
        set(case["dimensions_to_close"]) == {"performance"} for case in cases
    )
    base_economy = plan["execution_economy"]
    assert base_economy["blind_full_rerun"] is False
    assert base_economy["effectively_covered_preserved"] == 20
    assert base_economy["gap_objectives_planned"] == len(cases) == 30
    assert base_economy["rebind_labeled_cases"] == base_rebind_labeled_cases == 5
    assert base_economy["performance_rebind_only"] == base_performance_only_rebind_cases == 4
    assert base_economy["semantic_gap_cases"] == len(cases) - base_performance_only_rebind_cases == 26
    assert base_economy["designated_unseen_holdouts"] == 10

    augmented_ids: set[str] = set()
    for augmentation in addendum["augment_existing_cases"]:
        oid = augmentation["objective_id"]
        assert oid in base_case_by_objective, f"AUGMENT_TARGET_MISSING:{oid}"
        case = base_case_by_objective[oid]
        for dimension in augmentation["add_dimensions"]:
            assert dimension in expected_dimensions[oid], f"AUGMENT_DIMENSION_NOT_REQUIRED:{oid}:{dimension}"
            assert dimension not in case["dimensions_to_close"], f"AUGMENT_DIMENSION_ALREADY_PRESENT:{oid}:{dimension}"
            case["dimensions_to_close"].append(dimension)
        augmented_ids.add(oid)

    new_cases = addendum["new_cases"]
    assert all(case["objective_id"] not in base_case_by_objective for case in new_cases), "ADDENDUM_NEW_CASE_ALREADY_IN_BASE_PLAN"
    cases.extend(new_cases)

    case_ids = [case["case_id"] for case in cases]
    planned_objectives = [case["objective_id"] for case in cases]
    assert len(case_ids) == len(set(case_ids)), "DUPLICATE_CASE_ID"
    assert len(planned_objectives) == len(set(planned_objectives)), "DUPLICATE_OBJECTIVE_PLAN"
    assert set(planned_objectives) == gaps, {
        "missing_from_plan": sorted(gaps - set(planned_objectives)),
        "unexpected_in_plan": sorted(set(planned_objectives) - gaps),
    }

    holdouts_by_family: defaultdict[str, list[str]] = defaultdict(list)
    rebind_labeled_cases = 0
    performance_only_rebind_cases = 0
    for case in cases:
        oid = case["objective_id"]
        assert case["family"] == family_by_objective[oid], f"FAMILY_MISMATCH:{case['case_id']}"
        assert case["baseline"] == effective[oid], f"BASELINE_MISMATCH:{case['case_id']}:{case['baseline']}:{effective[oid]}"
        dims_to_close = set(case["dimensions_to_close"])
        assert dims_to_close == expected_dimensions[oid], f"DIMENSION_CLOSURE_MISMATCH:{case['case_id']}:{sorted(dims_to_close)}:{sorted(expected_dimensions[oid])}"
        assert str(case.get("failure_mode", "")).strip(), f"MISSING_FAILURE_MODE:{case['case_id']}"
        assert str(case.get("expected", "")).strip(), f"MISSING_EXPECTED:{case['case_id']}"
        assert str(case.get("learning", "")).strip(), f"MISSING_LEARNING:{case['case_id']}"
        assert case["prebuild_wave"] == "W0_PREBUILD_NOW", f"BAD_PREBUILD_WAVE:{case['case_id']}"
        assert case["final_wave"] in {"W1_FINAL_DETERMINISTIC", "W2_FINAL_MODEL_MATERIALIZATION", "W3_FINAL_STABILITY_AND_INDEPENDENT"}, f"BAD_FINAL_WAVE:{case['case_id']}"
        if case["unseen_holdout"]:
            holdouts_by_family[case["family"]].append(case["case_id"])
        if "REBIND" in case["closure_mode"]:
            rebind_labeled_cases += 1
        if dims_to_close == {"performance"}:
            performance_only_rebind_cases += 1

    assert set(holdouts_by_family) == family_ids, {
        "missing_holdout_families": sorted(family_ids - set(holdouts_by_family)),
        "extra_holdout_families": sorted(set(holdouts_by_family) - family_ids),
    }
    assert all(len(ids) == 1 for ids in holdouts_by_family.values()), dict(holdouts_by_family)
    actual_holdout_ids = {ids[0] for ids in holdouts_by_family.values()}
    declared_holdout_ids = set(plan["holdout_contract"]["holdout_cases"])
    assert actual_holdout_ids == declared_holdout_ids, {
        "holdout_missing": sorted(actual_holdout_ids - declared_holdout_ids),
        "holdout_extra": sorted(declared_holdout_ids - actual_holdout_ids),
    }
    assert len(actual_holdout_ids) == plan["holdout_contract"]["required_families"] == 10

    baseline_counts = Counter(effective.values())
    assert dict(baseline_counts) == addendum["projected_baseline_effective_counts"], (dict(baseline_counts), addendum["projected_baseline_effective_counts"])
    economy = addendum["execution_economy"]
    assert economy["effectively_covered_preserved"] == baseline_counts["COVERED"] == 17
    assert economy["gap_objectives_planned"] == len(gaps) == 33
    assert economy["rebind_labeled_cases"] == rebind_labeled_cases == 8
    assert economy["performance_rebind_only"] == performance_only_rebind_cases == 7
    assert economy["semantic_gap_cases"] == len(cases) - performance_only_rebind_cases == 26
    assert economy["designated_unseen_holdouts"] == len(actual_holdout_ids) == 10

    cross_bound = {item["objective_id"]: item for item in addendum["cross_bound_performance_evidence"]}
    assert set(cross_bound) == {"F08-O1", "F08-O2"}, f"BAD_CROSS_BOUND_SET:{sorted(cross_bound)}"
    for oid, item in cross_bound.items():
        policy = contract["na_policy"]["performance_na_reclassification"][oid]
        assert policy["effective_status"] == item["effective_performance"] == "COVERED"
        assert set(item["evidence_refs"]) == set(policy["required_evidence_refs"])
        assert item["independent_case_credit"] is False

    expected_augmented = {"F04-O2", "F04-O3", "F04-O4", "F06-O4", "F08-O3"}
    assert augmented_ids == expected_augmented, f"BAD_AUGMENTED_SET:{sorted(augmented_ids)}"
    assert {case["objective_id"] for case in new_cases} == {"F06-O2", "F06-O3", "F10-O4"}, "BAD_NEW_PERFORMANCE_REBIND_SET"

    waves = {wave["wave_id"]: wave for wave in plan["waves"]}
    assert waves["W0_PREBUILD_NOW"]["allowed_now"] is True
    assert all(waves[wave]["allowed_now"] is False for wave in ("W1_FINAL_DETERMINISTIC", "W2_FINAL_MODEL_MATERIALIZATION", "W3_FINAL_STABILITY_AND_INDEPENDENT"))
    assert plan["claim_ceiling"] == "PLAN_ONLY_NOT_EXECUTED_NOT_CERTIFIED_NOT_GATE_G_NOT_GOLDEN"
    assert addendum["claim_ceiling"] == "PLAN_CORRECTION_ONLY_NOT_EXECUTED_NOT_CERTIFIED_NOT_GATE_G_NOT_GOLDEN"

    summary = {
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_GAP_PLAN_VALIDATION_V2",
        "validation": "PASS",
        "effective_baseline": dict(baseline_counts),
        "preserved_covered": 17,
        "gap_objectives": len(gaps),
        "rebind_labeled_cases": rebind_labeled_cases,
        "performance_rebind_only": performance_only_rebind_cases,
        "semantic_gap_cases": len(cases) - performance_only_rebind_cases,
        "designated_unseen_holdouts": len(actual_holdout_ids),
        "holdout_families": len(holdouts_by_family),
        "performance_na_contract_reclassifications": len(contract["na_policy"]["performance_na_reclassification"]),
        "allowed_now": "W0_PREBUILD_NOW_ONLY",
        "final_execution_blocked_until_prerequisites": True,
        "system_certified": False,
    }
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
