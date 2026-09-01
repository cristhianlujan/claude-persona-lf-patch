"""Deterministic benchmark/negative tests for READ_ONLY Change Impact Resolver."""
from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))

from change_impact_resolver_readonly import ResolverContext, resolve

GOLD = ROOT / "sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql"
OVERLAY = HERE / "change_impact_l3c_adjudication_overlay_v1.json"


def parse_gold() -> list[dict]:
    text = GOLD.read_text(encoding="utf-8")
    rows = []
    line_re = re.compile(r"^\s*\('CI-[A-Z]+-\d{2}'.*\),?\s*$")
    for line in text.splitlines():
        if not line_re.match(line):
            continue
        literal = re.sub(r"''", r"\\'", line.strip().rstrip(","))
        try:
            row = ast.literal_eval(literal)
        except Exception as exc:
            raise AssertionError(f"GOLD_PARSE_FAILED:{line}") from exc
        if len(row) != 7:
            raise AssertionError(f"GOLD_ROW_SHAPE:{row[0]}")
        rows.append({
            "case_id": row[0], "case_family": row[1], "mutation": row[2],
            "expected_decision": row[3], "expected_impacts": set(json.loads(row[4])),
            "source_anchor": row[5], "rationale": row[6],
        })
    if len(rows) != 50:
        raise AssertionError(f"GOLD_CASE_COUNT:{len(rows)}")
    return rows


def apply_adjudication(rows: list[dict]) -> list[dict]:
    overlay = json.loads(OVERLAY.read_text(encoding="utf-8"))
    assert overlay["gold_status"] == "CANDIDATE_RESEARCH"
    assert overlay["authorization"] == {
        "scoped_pass_authorized": False, "downstream_authorized": False, "production_authorized": False,
    }
    by_id = {row["case_id"]: dict(row) for row in rows}
    for case_id, decision in overlay["decision_corrections"].items():
        by_id[case_id]["expected_decision"] = decision
    for case_id, additions in overlay["impact_additions"].items():
        by_id[case_id]["expected_impacts"] = set(by_id[case_id]["expected_impacts"]) | set(additions)
    for case_id, anchor in overlay["anchor_replacements"].items():
        by_id[case_id]["source_anchor"] = anchor
    return [by_id[row["case_id"]] for row in rows]


def evaluate():
    rows = apply_adjudication(parse_gold())
    ctx = ResolverContext(api_behavioral_contract=True, operation_schema_authority_materialized=False)
    decision_ok = tp = fp = fn = unsafe_under_block = unnecessary_global_block = 0
    unknown_count = mixed_count = shared_count = unknown_fail_closed = mixed_fail_closed = shared_fail_closed = 0
    depths = []
    for row in rows:
        result = resolve(row["case_family"], row["mutation"], ctx)
        decision_ok += int(result.decision == row["expected_decision"])
        tp += len(result.impacted_families & row["expected_impacts"])
        fp += len(result.impacted_families - row["expected_impacts"])
        fn += len(row["expected_impacts"] - result.impacted_families)
        depths.append(result.depth)
        unknown_count += int(result.unknown)
        mixed_count += int(result.mixed)
        shared_count += int(result.shared_dependency)
        unknown_fail_closed += int(result.unknown and result.fail_closed)
        mixed_fail_closed += int(result.mixed and result.fail_closed)
        shared_fail_closed += int(result.shared_dependency and result.fail_closed)
        if row["expected_decision"] in {"GLOBAL_ESCALATE", "HUMAN_REQUIRED"} and result.decision in {"SCOPED_CANDIDATE", "SCOPED_BLOCK"}:
            unsafe_under_block += 1
        if row["expected_decision"] in {"SCOPED_CANDIDATE", "SCOPED_BLOCK"} and result.decision == "GLOBAL_ESCALATE":
            unnecessary_global_block += 1
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    assert decision_ok == 50, f"DECISION_ACCURACY:{decision_ok}/50"
    assert precision == 1.0, f"IMPACT_PRECISION:{precision}"
    assert recall == 1.0, f"IMPACT_RECALL:{recall}"
    assert unsafe_under_block == 0, f"UNSAFE_UNDER_BLOCK:{unsafe_under_block}"
    assert unnecessary_global_block == 0, f"UNNECESSARY_GLOBAL_BLOCK:{unnecessary_global_block}"
    assert shared_count == 42, f"SHARED_COUNT:{shared_count}"
    assert unknown_count == unknown_fail_closed, (unknown_count, unknown_fail_closed)
    assert mixed_count == mixed_fail_closed, (mixed_count, mixed_fail_closed)

    negatives = [
        ("API_DATA_CONTRACT", "Crear endpoint alterno sin operation schema authority", "HUMAN_REQUIRED", True, True, False),
        ("FIELD_CONTRACT", "Agregar campo nuevo sin fuente canónica", "HUMAN_REQUIRED", True, True, False),
        ("PERMISSION_BINDING", "Reemplazar por permiso existente de otro recurso", "GLOBAL_ESCALATE", True, False, True),
        ("ACTION_SEMANTICS", "Cambiar action EXPORT -> DELETE", "GLOBAL_ESCALATE", True, False, False),
        ("STATE_TRANSITION", "Eliminar permission guard de transición", "GLOBAL_ESCALATE", True, False, False),
        ("DESIGN_COMPONENT", "Usar token DEPRECADO", "SCOPED_BLOCK", True, False, False),
        ("ACTION_SEMANTICS", "EXPORT permanece EXPORT", "SCOPED_CANDIDATE", False, False, False),
    ]
    for family, mutation, expected, fail_closed, unknown, mixed in negatives:
        result = resolve(family, mutation, ctx)
        assert result.decision == expected, (family, mutation, result.decision, expected)
        assert result.fail_closed is fail_closed
        assert result.unknown is unknown
        assert result.mixed is mixed

    print(json.dumps({
        "resolver_quality": {
            "cases": 50, "exact_decision_accuracy": decision_ok / 50,
            "impact_precision": precision, "impact_recall": recall,
            "unsafe_under_block": unsafe_under_block,
            "unnecessary_global_block": unnecessary_global_block,
            "unknown_cases": unknown_count, "unknown_fail_closed": unknown_fail_closed,
            "mixed_cases": mixed_count, "mixed_fail_closed": mixed_fail_closed,
            "shared_dependency_cases": shared_count, "shared_fail_closed": shared_fail_closed,
            "heldout_controls": len(negatives), "heldout_pass": len(negatives),
            "depth_min": min(depths), "depth_max": max(depths),
        },
        "authorization": {"scoped_pass_authorized": False, "downstream_authorized": False, "production_authorized": False},
    }, sort_keys=True))


if __name__ == "__main__":
    evaluate()
