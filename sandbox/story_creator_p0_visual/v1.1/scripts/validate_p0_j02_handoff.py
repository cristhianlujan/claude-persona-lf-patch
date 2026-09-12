#!/usr/bin/env python3
"""Fail-closed validator for the P0 -> Screen Decomposer handoff."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

from p0_schema import validate_instance
from validate_p0_judge import validate as validate_judge

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "schemas" / "p0-j02-handoff.schema.json"
HUMAN_DECISION_SCHEMA = ROOT / "schemas" / "human-review-decision.schema.json"
FIXTURES = ROOT / "evals" / "p0-contract-fixtures.json"
ARCHITECTURE_SHA256 = "a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531"


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def schema_errors_for(schema_path: Path, payload: Any) -> list[str]:
    schema = load(schema_path)
    return validate_instance(schema, payload)


def schema_errors(payload: Any) -> list[str]:
    return schema_errors_for(SCHEMA, payload)


def duplicate_count(items: Any, key: str) -> int:
    if not isinstance(items, list):
        return 1
    values = [item.get(key) for item in items if isinstance(item, dict) and isinstance(item.get(key), str)]
    return len(values) - len(set(values))


def validate(payload: Any) -> dict[str, Any]:
    errors = schema_errors(payload)
    if not isinstance(payload, dict):
        return {"result": "BLOCKED", "blocking_assertions": ["handoff_schema_invalid"], "checks": {}, "schema_errors": errors}
    decision = payload.get("effective_decision") if isinstance(payload.get("effective_decision"), dict) else {}
    judge_gate = validate_judge(decision)
    human = payload.get("human_review_decision") if isinstance(payload.get("human_review_decision"), dict) else {}
    human_present = isinstance(payload.get("human_review_decision"), dict)
    human_schema_errors = schema_errors_for(HUMAN_DECISION_SCHEMA, human) if human_present else []
    provenance = payload.get("provenance") if isinstance(payload.get("provenance"), dict) else {}
    actions = payload.get("action_inventory") if isinstance(payload.get("action_inventory"), list) else []
    contexts = payload.get("context_inventory") if isinstance(payload.get("context_inventory"), list) else []
    fields = payload.get("field_inventory") if isinstance(payload.get("field_inventory"), list) else []
    permissions = payload.get("permission_inventory") if isinstance(payload.get("permission_inventory"), list) else []
    transitions = payload.get("transition_inventory") if isinstance(payload.get("transition_inventory"), list) else []
    pending = payload.get("pending_decisions") if isinstance(payload.get("pending_decisions"), list) else []
    action_codes = {item.get("code") for item in actions if isinstance(item, dict)}
    context_codes = {item.get("code") for item in contexts if isinstance(item, dict)}
    expected_result = {"J00_P0_VISUAL_READING": "J00_READY_FOR_P1", "J00R_P0_REJUDGMENT": "J00R_READY_FOR_P1"}.get(decision.get("judge_code"))
    is_j00 = decision.get("judge_code") == "J00_P0_VISUAL_READING"
    is_j00r = decision.get("judge_code") == "J00R_P0_REJUDGMENT"
    adjudication_ref = decision.get("adjudication_overlay_ref")
    inventories = contexts + fields + actions
    checks = {
        "handoff_schema_invalid": len(errors),
        "architecture_source_mismatch": 0 if provenance.get("architecture_source_sha256") == ARCHITECTURE_SHA256 else 1,
        "decision_not_current": 0 if decision.get("is_current") is True else 1,
        "decision_superseded": 0 if decision.get("superseded_by") is None else 1,
        "decision_not_judged_ready": 0 if expected_result and decision.get("result") == expected_result else 1,
        "judge_decision_invalid": 0 if judge_gate.get("result") == "PASS_WITH_EVIDENCE" else 1,
        "j00_human_decision_unexpected": 1 if is_j00 and human_present else 0,
        "j00r_human_decision_missing": 1 if is_j00r and not human_present else 0,
        "j00r_human_decision_schema_invalid": len(human_schema_errors) if is_j00r else 0,
        "j00r_human_decision_not_routable": 1 if is_j00r and human.get("decision") not in {"CONFIRM_OBSERVATION", "CORRECT_WITH_ADJUDICATION"} else 0,
        "j00r_human_visual_hash_mismatch": 1 if is_j00r and human.get("visual_output_sha256") != payload.get("visual_output_sha256") else 0,
        "j00r_adjudication_overlay_mismatch": 1 if is_j00r and human.get("adjudication_overlay_ref") != adjudication_ref else 0,
        "j00r_adjudication_evidence_missing": 1 if is_j00r and adjudication_ref not in (payload.get("evidence_refs") or []) else 0,
        "worker_execution_mismatch": 0 if decision.get("worker_execution_id") == provenance.get("p0_execution_id") else 1,
        "visual_output_hash_mismatch": 0 if decision.get("visual_output_sha256") == payload.get("visual_output_sha256") else 1,
        "decision_evidence_missing": 0 if f"p0://decision/{decision.get('decision_id')}" in (payload.get("evidence_refs") or []) else 1,
        "blocking_pending_decisions": sum(1 for item in pending if isinstance(item, dict) and item.get("blocking") is True and item.get("status") == "OPEN"),
        "unresolved_inferred_inventory": sum(1 for item in inventories if isinstance(item, dict) and item.get("classification") == "INFERRED"),
        "duplicate_context_codes": duplicate_count(contexts, "code"),
        "duplicate_field_codes": duplicate_count(fields, "code"),
        "duplicate_action_codes": duplicate_count(actions, "code"),
        "duplicate_permission_codes": duplicate_count(permissions, "permission_code"),
        "fields_with_unknown_context": sum(1 for item in fields if isinstance(item, dict) and item.get("context_code") not in context_codes),
        "permissions_with_unknown_action": sum(1 for item in permissions if isinstance(item, dict) and item.get("action_code") not in action_codes),
        "transitions_with_unknown_action": sum(1 for item in transitions if isinstance(item, dict) and item.get("action") not in action_codes),
    }
    failed = sorted(key for key, value in checks.items() if value)
    return {
        "result": "PASS_WITH_EVIDENCE" if not failed else "BLOCKED",
        "blocking_assertions": failed,
        "checks": checks,
        "schema_errors": errors,
        "input_sha256": canonical_sha(payload),
        "decision_id": decision.get("decision_id"),
        "p0_execution_id": provenance.get("p0_execution_id"),
    }


def positive_fixture() -> dict[str, Any]:
    doc = load(FIXTURES)
    return copy.deepcopy(next(case["positive"] for case in doc["cases"] if case["schema"] == "p0-j02-handoff.schema.json"))


def self_test() -> int:
    good = positive_fixture()
    positive = validate(good)
    cases: list[tuple[str, dict[str, Any], str]] = []
    x = copy.deepcopy(good); x["effective_decision"]["is_current"] = False; cases.append(("stale_decision", x, "decision_not_current"))
    x = copy.deepcopy(good); x["effective_decision"]["superseded_by"] = "DEC-P0-2"; cases.append(("superseded_decision", x, "decision_superseded"))
    x = copy.deepcopy(good); x["effective_decision"]["result"] = "PENDING"; cases.append(("unjudged_decision", x, "decision_not_judged_ready"))
    x = copy.deepcopy(good); x["effective_decision"]["visual_output_sha256"] = "e" * 64; cases.append(("visual_hash_mismatch", x, "visual_output_hash_mismatch"))
    x = copy.deepcopy(good); x["context_inventory"][0]["classification"] = "INFERRED"; cases.append(("unresolved_inference", x, "unresolved_inferred_inventory"))
    x = copy.deepcopy(good); x["pending_decisions"] = [{"decision_code": "DEC-OPEN", "missing_fact": "Unknown permission", "why_required": "Required before story derivation", "blocking": True, "status": "OPEN"}]; cases.append(("blocking_pending_decision", x, "blocking_pending_decisions"))
    x = copy.deepcopy(good); x["permission_inventory"] = [{"permission_code": "PERM-ADMIN", "actor_profile": "ADMIN", "action_code": "DELETE", "source_ref": "policy://admin", "classification": "POLICY_CONFIRMED"}]; cases.append(("permission_unknown_action", x, "permissions_with_unknown_action"))
    x = copy.deepcopy(good); x["effective_decision"]["judge_code"] = "J00R_P0_REJUDGMENT"; x["effective_decision"]["result"] = "J00R_READY_FOR_P1"; cases.append(("j00r_without_adjudication", x, "judge_decision_invalid"))
    x = copy.deepcopy(good); x["effective_decision"]["judge_identity"] = x["effective_decision"]["worker_identity"]; cases.append(("judge_self_approval", x, "judge_decision_invalid"))
    outcomes = []
    for name, payload, expected in cases:
        result = validate(payload)
        outcomes.append({"name": name, "result": result["result"], "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})
    good_j00r = copy.deepcopy(good)
    good_j00r["effective_decision"].update({"decision_id": "DEC-P0R-1", "judge_code": "J00R_P0_REJUDGMENT", "result": "J00R_READY_FOR_P1", "judge_execution_id": "EXEC-J00R-1", "judge_identity": "AGENT-J00R-1", "adjudication_overlay_ref": "p0://adjudication/REV-1"})
    good_j00r["human_review_decision"] = {"review_id": "REV-1", "reviewer_identity": "USR-1", "reviewer_role": "P0_VISUAL_ADJUDICATOR", "decision": "CORRECT_WITH_ADJUDICATION", "visual_output_sha256": good_j00r["visual_output_sha256"], "adjudication_overlay_ref": "p0://adjudication/REV-1", "created_at": "2026-08-08T01:00:00Z"}
    good_j00r["evidence_refs"] = ["p0://decision/DEC-P0R-1", "p0://adjudication/REV-1"]
    positive_j00r = validate(good_j00r)
    x = copy.deepcopy(good_j00r); x["effective_decision"]["adjudication_overlay_ref"] = "x"; x["human_review_decision"]["adjudication_overlay_ref"] = "x"; x["evidence_refs"] = ["p0://decision/DEC-P0R-1"]; fake_overlay = validate(x)
    fake_overlay_blocked = fake_overlay["result"] == "BLOCKED" and ("judge_decision_invalid" in fake_overlay["blocking_assertions"] or "j00r_adjudication_evidence_missing" in fake_overlay["blocking_assertions"])
    passed = positive["result"] == "PASS_WITH_EVIDENCE" and positive_j00r["result"] == "PASS_WITH_EVIDENCE" and fake_overlay_blocked and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_pass": positive["result"] == "PASS_WITH_EVIDENCE", "positive_j00r_pass": positive_j00r["result"] == "PASS_WITH_EVIDENCE", "fake_overlay_blocked": fake_overlay_blocked, "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    result = validate(load(args.input))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
