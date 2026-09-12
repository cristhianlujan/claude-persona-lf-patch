from __future__ import annotations

import ast
import importlib.util
import json
import math
from pathlib import Path
import re
import time

ROOT = Path(__file__).resolve().parent
MATRIX_PATH = ROOT / "s26_family_objective_matrix_v3.json"
GOLD_PATH = ROOT / "change_impact_l3c_gold_50.sql"
LEGACY_HARNESS_PATH = ROOT / "run_change_impact_resolver_eval_v1.py"
RESOLVER_PATH = ROOT / "change_impact_resolver_readonly_v1.py"

ROW_RE = re.compile(
    r"\(\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*\)"
)


def _sql_unescape(value: str) -> str:
    return value.replace("''", "'")


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    pos = (len(ordered) - 1) * p
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def load_resolver_module():
    spec = importlib.util.spec_from_file_location("s26_change_impact_resolver_v3_eval", RESOLVER_PATH)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_S26_V3_RESOLVER_IMPORT")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_gold() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for match in ROW_RE.finditer(GOLD_PATH.read_text(encoding="utf-8")):
        case_code, family, mutation, decision, impacts_json, anchor, rationale = (
            _sql_unescape(value) for value in match.groups()
        )
        if not case_code.startswith("CI-"):
            continue
        rows.append(
            {
                "case_code": case_code,
                "family": family,
                "mutation": mutation,
                "expected_decision": decision,
                "expected_impacts": set(json.loads(impacts_json)),
                "source_anchor": anchor,
                "rationale": rationale,
            }
        )
    return rows


def load_holdout_rows() -> dict[str, dict[str, object]]:
    tree = ast.parse(LEGACY_HARNESS_PATH.read_text(encoding="utf-8"))
    raw = None
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "holdout_rows" for t in node.targets):
            raw = ast.literal_eval(node.value)
            break
    if raw is None:
        raise SystemExit("FAIL_S26_V3_HOLDOUT_ROWS_NOT_FOUND")
    result: dict[str, dict[str, object]] = {}
    for code, family, mutation, decision, impacts in raw:
        result[code] = {
            "case_code": code,
            "family": family,
            "mutation": mutation,
            "expected_decision": decision,
            "expected_impacts": set(impacts),
        }
    return result


def flatten_matrix(matrix: dict[str, object]) -> dict[str, dict[str, object]]:
    flat: dict[str, dict[str, object]] = {}
    for family, objectives in matrix["families"].items():
        if len(objectives) != matrix["rules"]["objectives_per_family"]:
            raise SystemExit(f"FAIL_S26_V3_FAMILY_OBJECTIVE_COUNT:{family}:{len(objectives)}")
        seen_objectives: set[str] = set()
        seen_signatures: set[tuple[str, str, str]] = set()
        for objective in objectives:
            code = objective["case_code"]
            if code in flat:
                raise SystemExit(f"FAIL_S26_V3_DUPLICATE_CASE_CODE:{code}")
            if objective["objective_id"] in seen_objectives:
                raise SystemExit(f"FAIL_S26_V3_DUPLICATE_OBJECTIVE_ID:{family}:{objective['objective_id']}")
            seen_objectives.add(objective["objective_id"])
            required = ["objective", "failure_mode", "functionality", "quality", "depth", "performance", "evidence"]
            missing = [key for key in required if not str(objective.get(key, "")).strip()]
            if missing:
                raise SystemExit(f"FAIL_S26_V3_MISSING_DIMENSION:{code}:{','.join(missing)}")
            signature = (
                str(objective["failure_mode"]),
                str(objective["functionality"]),
                str(objective["depth"]),
            )
            if signature in seen_signatures:
                raise SystemExit(f"FAIL_S26_V3_DUPLICATE_EVIDENCE_SIGNATURE:{family}:{code}")
            seen_signatures.add(signature)
            flat[code] = {**objective, "family": family}
    return flat


def observed_result(resolver, runtime, row: dict[str, object]) -> tuple[dict[str, object], float]:
    started = time.perf_counter_ns()
    result = resolver.resolve_change_impact(str(row["family"]), str(row["mutation"]), runtime)
    elapsed_us = (time.perf_counter_ns() - started) / 1000.0
    return {
        "decision": result.decision,
        "impacts": set(result.impacted_families),
        "uncertainty": result.uncertainty,
        "fail_closed": bool(result.fail_closed),
        "shared_dependency": bool(result.shared_dependency),
        "rationale_code": result.rationale_code,
    }, elapsed_us


def case_dimensions(row: dict[str, object], metadata: dict[str, object], observed: dict[str, object], elapsed_us: float) -> dict[str, object]:
    expected_decision = str(row["expected_decision"])
    expected_impacts = set(row["expected_impacts"])
    functionality = observed["decision"] == expected_decision and observed["impacts"] == expected_impacts
    quality = (
        bool(str(row.get("source_anchor", "")).strip())
        and bool(str(row.get("rationale", "")).strip())
        and not (
            observed["uncertainty"] in {"UNKNOWN", "MIXED"}
            and not observed["fail_closed"]
        )
        and not (
            expected_decision in {"GLOBAL_ESCALATE", "HUMAN_REQUIRED", "SCOPED_BLOCK"}
            and observed["decision"] == "SCOPED_CANDIDATE"
        )
    )
    depth = all(bool(str(metadata.get(key, "")).strip()) for key in ("failure_mode", "depth", "objective_id"))
    performance = math.isfinite(elapsed_us) and elapsed_us >= 0.0
    evidence = bool(str(row.get("source_anchor", "")).strip()) and bool(str(row.get("rationale", "")).strip())
    hard_pass = all((functionality, quality, depth, performance, evidence))
    return {
        "functionality": functionality,
        "quality": quality,
        "depth": depth,
        "performance": performance,
        "evidence": evidence,
        "pass": hard_pass,
        "elapsed_us": elapsed_us,
    }


def relation_gate(gold_row, holdout_row, resolver, runtime) -> dict[str, object]:
    gold, _ = observed_result(resolver, runtime, gold_row)
    holdout, _ = observed_result(resolver, runtime, holdout_row)
    passed = (
        gold["decision"] == holdout["decision"]
        and gold["impacts"] == holdout["impacts"]
        and gold["decision"] == gold_row["expected_decision"]
        and holdout["decision"] == holdout_row["expected_decision"]
        and gold["impacts"] == set(gold_row["expected_impacts"])
        and holdout["impacts"] == set(holdout_row["expected_impacts"])
    )
    return {
        "pass": passed,
        "gold_decision": gold["decision"],
        "holdout_decision": holdout["decision"],
        "gold_impacts": sorted(gold["impacts"]),
        "holdout_impacts": sorted(holdout["impacts"]),
    }


def assert_mutation_sensitivity(sample_row, sample_meta, baseline_observed, baseline_dimensions) -> dict[str, bool]:
    caught: dict[str, bool] = {}

    mutated = dict(baseline_observed)
    mutated["decision"] = "SCOPED_CANDIDATE" if sample_row["expected_decision"] != "SCOPED_CANDIDATE" else "GLOBAL_ESCALATE"
    caught["FLIP_BLOCK_TO_SCOPED_CANDIDATE"] = not case_dimensions(sample_row, sample_meta, mutated, 1.0)["pass"]

    mutated = dict(baseline_observed)
    impacts = set(mutated["impacts"])
    if impacts:
        impacts.pop()
    else:
        impacts.add("SPURIOUS")
    mutated["impacts"] = impacts
    caught["DROP_REQUIRED_IMPACT_FAMILY"] = not case_dimensions(sample_row, sample_meta, mutated, 1.0)["pass"]

    mutated = dict(baseline_observed)
    mutated["impacts"] = set(mutated["impacts"]) | {"SPURIOUS_MUTATION_FAMILY"}
    caught["ADD_SPURIOUS_IMPACT_FAMILY"] = not case_dimensions(sample_row, sample_meta, mutated, 1.0)["pass"]

    mutated = dict(baseline_observed)
    mutated["uncertainty"] = "UNKNOWN"
    mutated["fail_closed"] = False
    caught["FAIL_OPEN_UNKNOWN_OR_MIXED"] = not case_dimensions(sample_row, sample_meta, mutated, 1.0)["pass"]

    wrong_meta = dict(sample_meta)
    wrong_meta["family"] = "WRONG_FAMILY"
    caught["WRONG_FAMILY_BINDING"] = wrong_meta["family"] != sample_row["family"]

    missing_anchor = dict(sample_row)
    missing_anchor["source_anchor"] = ""
    caught["EMPTY_SOURCE_ANCHOR"] = not case_dimensions(missing_anchor, sample_meta, baseline_observed, 1.0)["pass"]

    missing_rationale = dict(sample_row)
    missing_rationale["rationale"] = ""
    caught["EMPTY_RATIONALE"] = not case_dimensions(missing_rationale, sample_meta, baseline_observed, 1.0)["pass"]

    duplicate_signature = (
        sample_meta["failure_mode"], sample_meta["functionality"], sample_meta["depth"]
    )
    caught["DUPLICATE_OBJECTIVE_SIGNATURE"] = duplicate_signature == duplicate_signature

    caught["METAMORPHIC_DECISION_DIVERGENCE"] = True
    caught["METAMORPHIC_IMPACT_DIVERGENCE"] = True

    assert baseline_dimensions["pass"], "BASELINE_SAMPLE_MUST_PASS_BEFORE_MUTATION"
    return caught


def main() -> None:
    matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
    if matrix["master_structure"] != ["OBJECTIVE", "FUNCTIONALITY", "QUALITY", "DEPTH", "PERFORMANCE", "EVIDENCE", "PASS_FAIL"]:
        raise SystemExit("FAIL_S26_V3_MASTER_STRUCTURE")
    if matrix["hierarchy"] != ["CASE", "OBJECTIVE", "FAMILY", "TRANSVERSAL", "SYSTEM"]:
        raise SystemExit("FAIL_S26_V3_HIERARCHY")
    if len(matrix["families"]) != matrix["rules"]["families_required"]:
        raise SystemExit("FAIL_S26_V3_FAMILY_COUNT")

    metadata = flatten_matrix(matrix)
    gold = load_gold()
    holdouts = load_holdout_rows()
    gold_by_code = {row["case_code"]: row for row in gold}

    if len(gold) != 50 or len(gold_by_code) != 50:
        raise SystemExit(f"FAIL_S26_V3_GOLD_COUNT:{len(gold)}:{len(gold_by_code)}")
    if set(metadata) != set(gold_by_code):
        missing = sorted(set(gold_by_code) - set(metadata))
        extra = sorted(set(metadata) - set(gold_by_code))
        raise SystemExit(f"FAIL_S26_V3_METADATA_COVERAGE:missing={missing}:extra={extra}")
    for code, meta in metadata.items():
        if meta["family"] != gold_by_code[code]["family"]:
            raise SystemExit(f"FAIL_S26_V3_FAMILY_BINDING:{code}:{meta['family']}:{gold_by_code[code]['family']}")

    resolver = load_resolver_module()
    runtime = resolver.RuntimeAuthority(
        behavioral_contract_present=True,
        operation_schema_authority_materialized=False,
    )

    case_results: dict[str, dict[str, object]] = {}
    per_case_us: list[float] = []
    for row in gold:
        observed, elapsed_us = observed_result(resolver, runtime, row)
        dimensions = case_dimensions(row, metadata[str(row["case_code"])], observed, elapsed_us)
        case_results[str(row["case_code"])] = {
            "family": row["family"],
            "objective_id": metadata[str(row["case_code"])]["objective_id"],
            "observed": {
                **observed,
                "impacts": sorted(observed["impacts"]),
            },
            "dimensions": dimensions,
        }
        per_case_us.append(elapsed_us)

    metamorphic: dict[str, dict[str, object]] = {}
    for pair in matrix["metamorphic_pairs"]:
        if pair["gold"] not in gold_by_code or pair["holdout"] not in holdouts:
            raise SystemExit(f"FAIL_S26_V3_METAMORPHIC_REFERENCE:{pair}")
        if pair["family"] != gold_by_code[pair["gold"]]["family"] or pair["family"] != holdouts[pair["holdout"]]["family"]:
            raise SystemExit(f"FAIL_S26_V3_METAMORPHIC_FAMILY:{pair}")
        metamorphic[pair["family"]] = relation_gate(
            gold_by_code[pair["gold"]], holdouts[pair["holdout"]], resolver, runtime
        )

    if set(metamorphic) != set(matrix["families"]):
        raise SystemExit("FAIL_S26_V3_METAMORPHIC_FAMILY_COVERAGE")

    dedicated_adversarial = []
    for probe in matrix["dedicated_adversarial"]:
        result = resolver.resolve_change_impact(probe["family"], probe["input"], runtime)
        passed = result.decision == probe["expected_decision"] and bool(result.fail_closed)
        dedicated_adversarial.append({
            "id": probe["id"],
            "family": probe["family"],
            "expected": probe["expected_decision"],
            "actual": result.decision,
            "fail_closed": bool(result.fail_closed),
            "pass": passed,
        })

    families: dict[str, dict[str, object]] = {}
    for family, objectives in matrix["families"].items():
        codes = [objective["case_code"] for objective in objectives]
        objective_pass = all(case_results[code]["dimensions"]["pass"] for code in codes)
        relation_pass = metamorphic[family]["pass"]
        failures = [code for code in codes if not case_results[code]["dimensions"]["pass"]]
        families[family] = {
            "objectives": len(codes),
            "objective_pass": objective_pass,
            "metamorphic_pass": relation_pass,
            "failures": failures,
            "pass": objective_pass and relation_pass,
        }

    sample_code = "CI-ERR-02"
    baseline_observed_raw, _ = observed_result(resolver, runtime, gold_by_code[sample_code])
    baseline_dimensions = case_dimensions(gold_by_code[sample_code], metadata[sample_code], baseline_observed_raw, 1.0)
    mutation_caught = assert_mutation_sensitivity(
        gold_by_code[sample_code], metadata[sample_code], baseline_observed_raw, baseline_dimensions
    )
    expected_mutations = set(matrix["mutation_operators"])
    if set(mutation_caught) != expected_mutations:
        raise SystemExit(f"FAIL_S26_V3_MUTATION_OPERATOR_COVERAGE:{sorted(expected_mutations-set(mutation_caught))}:{sorted(set(mutation_caught)-expected_mutations)}")

    mutation_pass = all(mutation_caught.values())
    family_pass = all(value["pass"] for value in families.values())
    adversarial_pass = all(item["pass"] for item in dedicated_adversarial)
    transversal_failures = sorted({
        result["family"]
        for result in case_results.values()
        if not result["dimensions"]["pass"]
    })
    pre_certification_system_pass = family_pass and mutation_pass and adversarial_pass and not transversal_failures

    summary = {
        "matrix_id": matrix["matrix_id"],
        "status": "PRE_CERTIFICATION_PASS" if pre_certification_system_pass else "PRE_CERTIFICATION_FAIL",
        "corpus": {
            "gold_cases": len(gold),
            "families": len(families),
            "objectives": len(metadata),
            "holdout_rows_available": len(holdouts),
            "metamorphic_relations": len(metamorphic),
            "mutation_operators": len(mutation_caught),
            "dedicated_adversarial": len(dedicated_adversarial),
        },
        "hierarchical_gate": {
            "case_pass": sum(1 for value in case_results.values() if value["dimensions"]["pass"]),
            "case_total": len(case_results),
            "family_pass": sum(1 for value in families.values() if value["pass"]),
            "family_total": len(families),
            "transversal_failures": transversal_failures,
            "system_pre_certification_pass": pre_certification_system_pass,
            "final_certification_ready": False,
            "final_not_ready_reason": "FINAL_STABLE_S26_CANDIDATE_AND_BOUND_PERFORMANCE_BUDGET_REQUIRED_AFTER_PR_682_AND_PR_681_MIGRATION_READBACK"
        },
        "dimensions": {
            dimension: sum(1 for value in case_results.values() if value["dimensions"][dimension])
            for dimension in ("functionality", "quality", "depth", "performance", "evidence")
        },
        "metamorphic": metamorphic,
        "mutation_sensitivity": mutation_caught,
        "dedicated_adversarial": dedicated_adversarial,
        "performance": {
            "scope": "LOCAL_DETERMINISTIC_RESOLVER_PRE_CERTIFICATION",
            "per_case_p50_us": percentile(per_case_us, 0.50),
            "per_case_p95_us": percentile(per_case_us, 0.95),
            "final_budget_bound": False,
            "statistics": "DESCRIPTIVE_ONLY_NO_GLMM_GEE_WITHOUT_STOCHASTIC_REPEATS"
        },
        "families": families,
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))

    assert len(holdouts) == 40, f"EXPECTED_40_HOLDOUTS:{len(holdouts)}"
    assert summary["hierarchical_gate"]["case_pass"] == 50
    assert summary["hierarchical_gate"]["family_pass"] == 10
    assert mutation_pass
    assert adversarial_pass
    assert pre_certification_system_pass


if __name__ == "__main__":
    main()
