#!/usr/bin/env python3
"""N-6 NEGATIVE_ESCALATE: business definition / source conflict / non-literal value => HUMAN_DECISION_REQUIRED, never auto-completed.

Judges an authority snapshot taken from the live Supabase function inside always-rolled-back scenarios (run 520, pantalla 49).
Mutations affect Python copies only; no database writes.
"""
from __future__ import annotations
import argparse
import copy
import json
import sys
from pathlib import Path

TEST_CODE = "ENG_N6_NEGATIVE_ESCALATE"
ESCALATION_REASONS = {
    "EXACT_POSITIVE_COMPONENT_AUTHORITY_NOT_PRESENT": "HUMAN_DECISION_REQUIRED",
    "SOURCE_CONFLICT_MULTIPLE_EXPLICIT_COMPONENT_CODES": "HUMAN_DECISION_REQUIRED",
    "SOURCE_RULE_PENDING_DECISION": "HUMAN_DECISION_REQUIRED",
    "SOURCE_RULE_NOT_FOUND_OR_NOT_ACTIVE": "HUMAN_DECISION_REQUIRED",
    "EXACT_TARGET_NOT_UNIQUE_VIGENTE": "HUMAN_DECISION_REQUIRED",
}
REQUIRED_KINDS = {"BUSINESS_DEFINITION_ABSENT", "NON_LITERAL_VALUE", "SOURCE_CONFLICT",
                  "BUSINESS_DEFINITION_PENDING", "SOURCE_UNVERIFIABLE", "TARGET_AMBIGUOUS"}
EXPECTED_REASON_BY_KIND = {
    "SOURCE_CONFLICT": "SOURCE_CONFLICT_MULTIPLE_EXPLICIT_COMPONENT_CODES",
    "BUSINESS_DEFINITION_PENDING": "SOURCE_RULE_PENDING_DECISION",
    "SOURCE_UNVERIFIABLE": "SOURCE_RULE_NOT_FOUND_OR_NOT_ACTIVE",
    "TARGET_AMBIGUOUS": "EXACT_TARGET_NOT_UNIQUE_VIGENTE",
}


def escalation_gate(authority: dict) -> bool:
    """Structural + semantic judge over the live rolled-back snapshot."""
    if authority.get("source") != "SUPABASE_LIVE_CANONICAL_ROLLED_BACK":
        return False
    if authority.get("function") != "programacion.fn_input_governance_safe_autofix_v1":
        return False
    if authority.get("persisted_rows_after_all_scenarios") != 0:
        return False
    elements = [str(e) for e in authority.get("elements", [])]
    scenarios = authority.get("scenarios")
    if not elements or not isinstance(scenarios, list) or not scenarios:
        return False
    names = [s.get("name") for s in scenarios]
    if len(set(names)) != len(names) or not all(names):
        return False
    kinds = {s.get("kind") for s in scenarios}
    if "POSITIVE" not in kinds or not REQUIRED_KINDS.issubset(kinds):
        return False
    for s in scenarios:
        actions, before, after = s.get("actions"), s.get("before"), s.get("after")
        if not (isinstance(actions, dict) and isinstance(before, dict) and isinstance(after, dict)):
            return False
        if set(actions) != set(elements) or set(before) != set(elements) or set(after) != set(elements):
            return False
        binds = [e for e, a in actions.items() if a.get("a") == "BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN"]
        nowrites = [e for e, a in actions.items() if a.get("a") == "NO_WRITE"]
        if len(binds) + len(nowrites) != len(elements):
            return False
        if s.get("applied") != len(binds) or s.get("skipped") != len(nowrites):
            return False
        for e in nowrites:
            reason = actions[e].get("reason")
            if ESCALATION_REASONS.get(reason) != "HUMAN_DECISION_REQUIRED":
                return False
            if after[e] != before[e]:
                return False  # a NO_WRITE element must stay byte-identical: never auto-completed
        if s["kind"] == "POSITIVE":
            if len(binds) != 1:
                return False
            e = binds[0]
            if after[e].get("tok") is None or after[e].get("b") != "RESOLVED_ID":
                return False
            continue
        # every negative scenario: nothing may be written
        if binds or s.get("applied") != 0:
            return False
        if any(after[e].get("tok") is not None or after[e].get("b") != "PENDING_SEMANTIC_COMPONENT" for e in elements):
            return False
        expected = EXPECTED_REASON_BY_KIND.get(s["kind"])
        if expected and not any(a.get("reason") == expected for a in actions.values()):
            return False
        if s["kind"] == "SOURCE_CONFLICT" and not (isinstance(s.get("conflicts"), int) and s["conflicts"] >= 1):
            return False
        if s["kind"] != "SOURCE_CONFLICT" and s.get("conflicts") != 0:
            return False
    return True


def negative_campaign(authority: dict) -> dict:
    if not escalation_gate(authority):
        raise AssertionError("POSITIVE_LIVE_SNAPSHOT_NOT_ACCEPTED")
    results = {"baseline_live_snapshot": True}
    cases: dict[str, dict] = {}

    def mutate(name, fn):
        c = copy.deepcopy(authority)
        fn(c)
        cases[name] = c

    def sc(c, name):
        return next(s for s in c["scenarios"] if s["name"] == name)

    mutate("forged_source", lambda c: c.__setitem__("source", "FIXTURE"))
    mutate("persisted_rows_leak", lambda c: c.__setitem__("persisted_rows_after_all_scenarios", 1))
    mutate("conflict_autocompleted", lambda c: (sc(c, "source_conflict_two_codes").__setitem__("applied", 1),
                                                 sc(c, "source_conflict_two_codes")["actions"]["251"].update(a="BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN", reason=None)))
    mutate("pending_rule_element_mutated", lambda c: sc(c, "rule_pending_decision")["after"]["252"].update(tok=2, b="RESOLVED_ID"))
    mutate("unknown_reason_not_escalated", lambda c: sc(c, "rule_not_found")["actions"]["253"].update(reason="SILENTLY_IGNORED"))
    mutate("no_authority_wrote_token", lambda c: sc(c, "no_authority_at_all")["after"]["250"].update(tok=1))
    mutate("non_literal_status_flipped", lambda c: sc(c, "non_literal_rule_only")["after"]["238"].update(st="VIGENTE"))
    mutate("conflict_count_hidden", lambda c: sc(c, "source_conflict_two_codes").__setitem__("conflicts", 0))
    mutate("ambiguous_target_not_noted", lambda c: sc(c, "token_not_unique_vigente")["actions"]["238"].update(reason="EXACT_POSITIVE_COMPONENT_AUTHORITY_NOT_PRESENT"))
    mutate("category_removed", lambda c: c.__setitem__("scenarios", [s for s in c["scenarios"] if s["kind"] != "SOURCE_CONFLICT"]))
    mutate("positive_control_lost", lambda c: sc(c, "positive_vigente_bind").__setitem__("applied", 0))
    mutate("positive_not_resolved", lambda c: sc(c, "positive_vigente_bind")["after"]["238"].update(b="PENDING_SEMANTIC_COMPONENT"))
    mutate("duplicate_scenario_name", lambda c: c["scenarios"].append(copy.deepcopy(c["scenarios"][0])))
    mutate("count_mismatch", lambda c: sc(c, "no_authority_at_all").__setitem__("skipped", 4))

    for name, candidate in cases.items():
        if escalation_gate(candidate):
            raise AssertionError(f"NEGATIVE_NOT_DETECTED:{name}")
        results[name] = True

    return {
        "status": "PASS",
        "test_code": TEST_CODE,
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "semantic_authority_scope": "SAFE_AUTOFIX_ESCALATION_ROLLED_BACK_LIVE",
        "adversarial_case_executed": True,
        "selected_run_id": authority["run_id"],
        "scenarios_judged": len(authority["scenarios"]),
        "negative_cases_detected": len(cases),
        "tests_passed": len(results),
        "tests_total": len(results),
        "controls": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--authority-json", type=Path, required=True)
    args = parser.parse_args()
    authority = json.loads(args.authority_json.read_text(encoding="utf-8"))
    print(json.dumps(negative_campaign(authority), sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, KeyError, ValueError, TypeError, StopIteration) as error:
        print(json.dumps({"status": "FAIL", "test_code": TEST_CODE, "test_passed": False,
                          "test_exit_code": 1, "error": str(error)}))
        sys.exit(1)
