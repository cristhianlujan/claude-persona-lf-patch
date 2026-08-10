#!/usr/bin/env python3
"""Conservative reproducible scorer for creating-integral-user-stories.

The scorer operationalizes the package formula MIN(CLAUDE,GITHUB,TECHNICAL)
without turning a numeric result into approval. At least two genuinely
independent evaluator identities/executions are required. Quality-10 eligibility
also requires every hard evidence gate, including real visual runtime and
resolved provenance. Provenance resolution does not force a derived artifact
from INFERRED to CONFIRMED.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

AXES = ("CLAUDE", "GITHUB", "TECHNICAL")
HARD_GATES = (
    "external_positive_executed",
    "negative_rejected",
    "blocking_case_executed",
    "runtime_chain_executed",
    "visual_runtime_proven",
    "provenance_resolved",
    "source_completeness_executed",
    "github_supabase_reconciled",
)


def schema_path() -> Path:
    return Path(__file__).resolve().parent.parent / "schemas" / "maturity-score-input.schema.json"


def validate_schema(payload: dict[str, Any]) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise SystemExit("jsonschema_not_available") from exc
    schema = json.loads(schema_path().read_text(encoding="utf-8"))
    jsonschema.Draft7Validator.check_schema(schema)
    validator = jsonschema.Draft7Validator(schema)
    return sorted(
        f"{'/'.join(map(str, err.absolute_path)) or '$'}:{err.message}"
        for err in validator.iter_errors(payload)
    )


def unwrap_input(payload: dict[str, Any]) -> dict[str, Any]:
    """Accept either the raw score contract or the governed fixture envelope."""
    fixture = payload.get("fixture")
    if isinstance(fixture, dict) and isinstance(fixture.get("score_input"), dict):
        return fixture["score_input"]
    return payload


def score(payload: dict[str, Any]) -> dict[str, Any]:
    payload = unwrap_input(payload)
    schema_errors = validate_schema(payload)
    evaluations = payload.get("evaluations") if isinstance(payload.get("evaluations"), list) else []

    identities = [str(e.get("evaluator_identity") or "").strip() for e in evaluations if isinstance(e, dict)]
    executions = [str(e.get("execution_id") or "").strip() for e in evaluations if isinstance(e, dict)]
    independent = (
        len(evaluations) >= 2
        and len(identities) == len(set(identities))
        and len(executions) == len(set(executions))
        and all(identities)
        and all(executions)
    )

    evaluator_results: list[dict[str, Any]] = []
    for evaluation in evaluations:
        if not isinstance(evaluation, dict):
            continue
        axes = evaluation.get("axes") if isinstance(evaluation.get("axes"), dict) else {}
        axis_scores = {
            axis: float((axes.get(axis) or {}).get("score", 0.0))
            for axis in AXES
        }
        evaluator_floor = min(axis_scores.values()) if axis_scores else 0.0
        evaluator_results.append({
            "evaluator_identity": evaluation.get("evaluator_identity"),
            "execution_id": evaluation.get("execution_id"),
            "axis_scores": axis_scores,
            "formula": "MIN(CLAUDE,GITHUB,TECHNICAL)",
            "evaluator_floor_score": round(evaluator_floor, 4),
        })

    package_score = (
        round(min(x["evaluator_floor_score"] for x in evaluator_results), 4)
        if evaluator_results else None
    )
    threshold = float(payload.get("threshold", 9.5))
    hard_gates = payload.get("hard_gates") if isinstance(payload.get("hard_gates"), dict) else {}
    missing_hard_gates = [gate for gate in HARD_GATES if hard_gates.get(gate) is not True]
    threshold_met = package_score is not None and package_score > threshold
    quality_10_eligible = (
        not schema_errors
        and independent
        and threshold_met
        and not missing_hard_gates
    )

    blockers: list[str] = []
    if schema_errors:
        blockers.append("INPUT_SCHEMA_INVALID")
    if not independent:
        blockers.append("INDEPENDENT_EVALUATOR_RECEIPTS_REQUIRED")
    if not threshold_met:
        blockers.append("CONSERVATIVE_SCORE_THRESHOLD_NOT_MET")
    blockers.extend(f"HARD_GATE_MISSING:{gate}" for gate in missing_hard_gates)

    return {
        "schema_version": "package-maturity-score-result/v0.1",
        "package_code": payload.get("package_code"),
        "score_formula": "MIN(each evaluator MIN(CLAUDE,GITHUB,TECHNICAL))",
        "threshold_rule": f"package_score > {threshold:g}",
        "schema_errors": schema_errors,
        "independent_evaluators": independent,
        "evaluator_count": len(evaluator_results),
        "evaluator_results": evaluator_results,
        "package_score": package_score,
        "threshold_met": threshold_met,
        "hard_gates": {gate: hard_gates.get(gate) is True for gate in HARD_GATES},
        "missing_hard_gates": missing_hard_gates,
        "quality_10_eligible": quality_10_eligible,
        "blockers": blockers,
        "promotion_authorized": False,
        "numeric_score_is_approval": False,
    }


def synthetic_payload() -> dict[str, Any]:
    def evaluation(identity: str, execution: str, scores: tuple[float, float, float]) -> dict[str, Any]:
        return {
            "evaluator_identity": identity,
            "execution_id": execution,
            "evaluation_kind": "EXTERNAL_INDEPENDENT",
            "axes": {
                axis: {"score": value, "evidence_refs": [f"synthetic://{identity}/{axis.lower()}"]}
                for axis, value in zip(AXES, scores)
            },
        }
    return {
        "schema_version": "package-maturity-score-input/v0.1",
        "package_code": "creating-integral-user-stories",
        "threshold": 9.5,
        "evaluations": [
            evaluation("EVAL-A", "EXEC-SCORE-A", (9.8, 9.7, 9.9)),
            evaluation("EVAL-B", "EXEC-SCORE-B", (9.7, 9.8, 9.6)),
        ],
        "hard_gates": {gate: True for gate in HARD_GATES},
    }


def self_test() -> int:
    cases: list[dict[str, Any]] = []

    good = synthetic_payload()
    result = score(good)
    cases.append({
        "case": "eligible_two_independent_evaluators",
        "passed": result["quality_10_eligible"] is True and result["package_score"] == 9.6,
        "observed": result,
    })

    duplicate = copy.deepcopy(good)
    duplicate["evaluations"][1]["evaluator_identity"] = duplicate["evaluations"][0]["evaluator_identity"]
    result = score(duplicate)
    cases.append({
        "case": "duplicate_evaluator_identity_blocked",
        "passed": result["quality_10_eligible"] is False and "INDEPENDENT_EVALUATOR_RECEIPTS_REQUIRED" in result["blockers"],
        "observed": result,
    })

    no_visual = copy.deepcopy(good)
    no_visual["hard_gates"]["visual_runtime_proven"] = False
    result = score(no_visual)
    cases.append({
        "case": "visual_runtime_missing_blocks_quality10",
        "passed": result["quality_10_eligible"] is False and "HARD_GATE_MISSING:visual_runtime_proven" in result["blockers"],
        "observed": result,
    })

    no_provenance = copy.deepcopy(good)
    no_provenance["hard_gates"]["provenance_resolved"] = False
    result = score(no_provenance)
    cases.append({
        "case": "unresolved_provenance_blocks_quality10",
        "passed": result["quality_10_eligible"] is False and "HARD_GATE_MISSING:provenance_resolved" in result["blockers"],
        "observed": result,
    })

    low = copy.deepcopy(good)
    low["evaluations"][1]["axes"]["TECHNICAL"]["score"] = 9.5
    result = score(low)
    cases.append({
        "case": "exclusive_threshold_enforced",
        "passed": result["quality_10_eligible"] is False and result["package_score"] == 9.5,
        "observed": result,
    })

    envelope = {
        "fixture": {"score_input": copy.deepcopy(good)},
        "fixture_id": "SYNTHETIC-ENVELOPE",
    }
    result = score(envelope)
    cases.append({
        "case": "governed_fixture_envelope_unwrapped",
        "passed": result["quality_10_eligible"] is True and result["package_score"] == 9.6,
        "observed": result,
    })

    ok = all(item["passed"] for item in cases)
    print(json.dumps({"self_test_pass": ok, "cases": cases}, ensure_ascii=False, sort_keys=True))
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise SystemExit("input_required")
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit("input_must_be_object")
    result = score(payload)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if not result["schema_errors"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
