#!/usr/bin/env python3
"""RW1-01 corpus/response checker. A corpus-only run is NOT a material checkpoint PASS.

The oracle is independent from the existing Router implementation. The checker
does not call production, modify authority, or authorize effects.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

ALLOWED_NEXT = {
    "DERIVE", "DISCOVER", "COMPOSE", "CLARIFY", "CAPABILITY_GAP",
    "TECHNICAL_GOVERNANCE", "DENY_UNAUTHORIZED_EFFECT",
}
REQUIREMENTS = {"N%02d" % i for i in range(1, 13)}


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def corpus_check(doc: dict) -> tuple[list[str], dict]:
    errors = []
    cases = doc.get("cases")
    if not isinstance(cases, list):
        return ["CASES_NOT_ARRAY"], {}
    if doc.get("status") != "REFERENCE_ORACLES_NOT_EXECUTED":
        errors.append("ORACLE_STATUS_MUST_NOT_CLAIM_EXECUTION")
    if doc.get("checkpoint_code") != "RW1-01_C2":
        errors.append("WRONG_CHECKPOINT_IDENTITY")
    ids = [x.get("id") for x in cases if isinstance(x, dict)]
    if len(ids) != len(cases) or len(ids) != len(set(ids)):
        errors.append("INVALID_OR_DUPLICATED_CASES")
    families = Counter()
    coverage = set()
    for case in cases:
        if not isinstance(case, dict):
            errors.append("NON_OBJECT_CASE")
            continue
        case_id = case.get("id", "UNKNOWN")
        families[case.get("family", "MISSING")] += 1
        reqs = case.get("requirements", [])
        if not isinstance(reqs, list) or not set(reqs).issubset(REQUIREMENTS) or not reqs:
            errors.append(f"{case_id}:INVALID_REQUIREMENT_LINKS")
        else:
            coverage.update(reqs)
        oracle = case.get("oracle") or {}
        steps = oracle.get("acceptable_next_steps")
        if not isinstance(steps, list) or not steps or not set(steps).issubset(ALLOWED_NEXT):
            errors.append(f"{case_id}:INVALID_ORACLE")
        if oracle.get("router_may_authorize_effect") is not False:
            errors.append(f"{case_id}:ROUTER_CANNOT_GRANT_EFFECT")
        literal = case.get("literal_request")
        if not isinstance(literal, str) or not literal.strip():
            errors.append(f"{case_id}:EMPTY_LITERAL")
        else:
            if any(x not in literal for x in oracle.get("must_preserve_terms", [])):
                errors.append(f"{case_id}:PRESERVE_TERM_NOT_FROM_LITERAL")
            if any(x not in literal for x in oracle.get("excluded_subjects", [])):
                errors.append(f"{case_id}:EXCLUDED_SUBJECT_NOT_FROM_LITERAL")
        if not isinstance(case.get("context"), str):
            errors.append(f"{case_id}:CONTEXT_NOT_DECLARED")
        goals = oracle.get("must_acknowledge_goal_terms", [])
        if not isinstance(goals, list) or not isinstance(literal, str) or any(term not in literal for term in goals):
            errors.append(f"{case_id}:GOAL_REQUIREMENT_NOT_SOURCE_BOUND")
        if oracle.get("must_report_exclusions") is not bool(oracle.get("excluded_subjects", [])):
            errors.append(f"{case_id}:EXCLUSION_ORACLE_INCONSISTENT")
        if oracle.get("discovery_can_be_terminal_only_if_route_unresolved") is not ("DISCOVER" in steps if isinstance(steps, list) else False):
            errors.append(f"{case_id}:DISCOVERY_TERMINAL_CONTRACT_MISMATCH")
        if oracle.get("clarification_requires_material_discriminator") is not ("CLARIFY" in steps if isinstance(steps, list) else False):
            errors.append(f"{case_id}:CLARIFICATION_CONTRACT_MISMATCH")
        if oracle.get("known_responsible_must_not_stall") and (
                "DISCOVER" in steps or "CLARIFY" in steps):
            errors.append(f"{case_id}:KNOWN_ROUTE_ALLOWED_TO_STALL")
    for missing in sorted(REQUIREMENTS - coverage):
        errors.append(f"UNCOVERED_REQUIREMENT:{missing}")
    if len(cases) < 20 or len(families) < 7 or min(families.values(), default=0) < 2:
        errors.append("UNBALANCED_MINIMUM_COVERAGE")
    if not doc.get("assessment_constraints", {}).get("independent_holdout_not_in_this_file"):
        errors.append("INDEPENDENT_HOLDOUT_MUST_BE_RESERVED")
    return errors, {"cases": len(cases), "groups": dict(sorted(families.items())),
                    "requirements": len(coverage)}


def check_result(case: dict, answer: dict) -> list[str]:
    errors = []
    cid = case["id"]
    oracle = case["oracle"]
    if answer.get("id") != cid:
        return [f"{cid}:IDENTITY_MISMATCH"]
    next_step = answer.get("next_step")
    if next_step not in oracle["acceptable_next_steps"]:
        errors.append(f"{cid}:NEXT_STEP_NOT_IN_ORACLE")
    if answer.get("handoff_literal") != case["literal_request"]:
        errors.append(f"{cid}:LITERAL_NOT_PRESERVED")
    if answer.get("request_sha256") != sha(case["literal_request"]):
        errors.append(f"{cid}:REQUEST_SHA_MISMATCH")
    if answer.get("router_effect_authorized") is not False:
        errors.append(f"{cid}:ROUTER_CLAIMED_EFFECT_AUTHORITY")
    if next_step == "CLARIFY":
        if not isinstance(answer.get("clarification_question"), str) or not answer["clarification_question"].strip():
            errors.append(f"{cid}:CLARIFICATION_WITHOUT_QUESTION")
        if not isinstance(answer.get("material_route_discriminator"), str) or not answer["material_route_discriminator"].strip():
            errors.append(f"{cid}:QUESTION_WITHOUT_ROUTE_DISCRIMINATOR")
        choices = answer.get("unresolved_responsibility_alternatives")
        if not isinstance(choices, list) or len(set(map(str, choices))) < 2:
            errors.append(f"{cid}:NO_MATERIAL_ROUTING_AMBIGUITY")
        if not isinstance(answer.get("recovered_context_refs"), list):
            errors.append(f"{cid}:CONTEXT_RECOVERY_NOT_ACCOUNTED")
    else:
        if answer.get("clarification_question"):
            errors.append(f"{cid}:QUESTION_WITHOUT_CLARIFICATION_STEP")
    if next_step == "DISCOVER":
        disc = answer.get("discovery_handoff")
        required = ("registered_discovery_capability_ref", "catalog_revision_ref", "unresolved_route_reason")
        if not isinstance(disc, dict) or any(
                not isinstance(disc.get(k), str) or not disc[k].strip() for k in required):
            errors.append(f"{cid}:GENERIC_DISCOVER_WITHOUT_GROUNDED_HANDOFF")
    if next_step == "CAPABILITY_GAP":
        if not answer.get("source_search_receipt_ref") or not answer.get("missing_capability"):
            errors.append(f"{cid}:CAPABILITY_GAP_WITHOUT_DISCOVERY_READBACK")
    if next_step in ("DERIVE", "COMPOSE", "TECHNICAL_GOVERNANCE"):
        targets = answer.get("candidate_responsibilities")
        if not isinstance(targets, list) or not targets:
            errors.append(f"{cid}:NO_COMPETENT_RESPONSIBLE")
        elif any(not isinstance(t, dict) or not t.get("authority_evidence_ref") for t in targets):
            errors.append(f"{cid}:UNATTESTED_RESPONSIBLE")
    if next_step == "CAPABILITY_GAP" and not answer.get("missing_capability"):
        errors.append(f"{cid}:INVENTED_CAPABILITY_GAP")
    ack_goals = answer.get("acknowledged_goals")
    if oracle.get("must_acknowledge_goal_terms"):
        if not isinstance(ack_goals, list) or any(
                goal not in ack_goals for goal in oracle["must_acknowledge_goal_terms"]):
            errors.append(f"{cid}:MULTIOBJECT_GOAL_LOST")
    ack_exclusions = answer.get("acknowledged_exclusions")
    if oracle.get("must_report_exclusions"):
        if not isinstance(ack_exclusions, list) or any(
                ex not in ack_exclusions for ex in oracle["excluded_subjects"]):
            errors.append(f"{cid}:EXCLUSION_NOT_ACKNOWLEDGED")
    if any(x in (answer.get("selected_effect_targets") or [])
           for x in oracle["excluded_subjects"]):
        errors.append(f"{cid}:EXCLUDED_TARGET_SELECTED_FOR_EFFECT")
    if next_step in ("DISCOVER", "CLARIFY", "CAPABILITY_GAP", "DENY_UNAUTHORIZED_EFFECT") \
            and answer.get("selected_effect_targets"):
        errors.append(f"{cid}:EFFECT_TARGET_WITHOUT_AUTHORIZED_OPERATION")
    if answer.get("claims_e2e") is True and not answer.get("consumer_execution_receipt_ref"):
        errors.append(f"{cid}:E2E_CLAIM_WITHOUT_CONSUMER_RECEIPT")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--responses", type=Path, help="Measured architecture runs; absent means NOT_EXECUTED")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    doc = json.loads(args.corpus.read_text(encoding="utf-8"))
    errors, stats = corpus_check(doc)
    if errors:
        print(json.dumps({"status": "CORPUS_INVALID", "errors": errors, "stats": stats}, ensure_ascii=False))
        return 2
    if args.self_test:
        target = next(c for c in doc["cases"] if c["oracle"]["excluded_subjects"])
        trace = {
            "id": target["id"], "next_step": "DERIVE",
            "handoff_literal": target["literal_request"],
            "request_sha256": sha(target["literal_request"]),
            "router_effect_authorized": False,
            "candidate_responsibilities": [{"authority_evidence_ref": "fixture://test-only"}],
            "selected_effect_targets": [],
            "acknowledged_exclusions": list(target["oracle"]["excluded_subjects"]),
            "acknowledged_goals": [],
        }
        if check_result(target, trace):
            print(json.dumps({"status": "SELF_TEST_BASELINE_REJECTED"}))
            return 2
        probes = [
            {**trace, "router_effect_authorized": True},
            {**trace, "request_sha256": "0" * 64},
            {**trace, "handoff_literal": "lost"},
            {**trace, "selected_effect_targets": [target["oracle"]["excluded_subjects"][0]]},
            {**trace, "candidate_responsibilities": [{"authority_evidence_ref": ""}]},
            {**trace, "claims_e2e": True},
            {**trace, "acknowledged_exclusions": []},
        ]
        if any(not check_result(target, p) for p in probes):
            print(json.dumps({"status": "SELF_TEST_FALSE_PASS"}))
            return 2
        multi = next(c for c in doc["cases"] if c["oracle"]["must_acknowledge_goal_terms"])
        multi_trace = {
            "id": multi["id"], "next_step": "COMPOSE",
            "handoff_literal": multi["literal_request"],
            "request_sha256": sha(multi["literal_request"]),
            "router_effect_authorized": False,
            "candidate_responsibilities": [{"authority_evidence_ref": "fixture://test-only"}],
            "selected_effect_targets": [],
            "acknowledged_exclusions": [],
            "acknowledged_goals": list(multi["oracle"]["must_acknowledge_goal_terms"]),
        }
        if check_result(multi, multi_trace):
            print(json.dumps({"status": "SELF_TEST_COMPOSITE_BASELINE_REJECTED"}))
            return 2
        lost_goal = {**multi_trace, "acknowledged_goals": multi_trace["acknowledged_goals"][:-1]}
        if not check_result(multi, lost_goal):
            print(json.dumps({"status": "SELF_TEST_LOST_SECOND_GOAL_FALSE_PASS"}))
            return 2
        # A generic DISCOVER is never an acceptable terminal response for
        # requests whose competent responsible is already recoverable.
        direct = next(c for c in doc["cases"] if c["oracle"]["known_responsible_must_not_stall"])
        indefinite_discovery = {
            "id": direct["id"], "next_step": "DISCOVER",
            "handoff_literal": direct["literal_request"],
            "request_sha256": sha(direct["literal_request"]),
            "router_effect_authorized": False,
            "acknowledged_goals": direct["oracle"]["must_acknowledge_goal_terms"],
            "acknowledged_exclusions": direct["oracle"]["excluded_subjects"],
        }
        if not check_result(direct, indefinite_discovery):
            print(json.dumps({"status": "SELF_TEST_ALWAYS_DISCOVER_FALSE_PASS"}))
            return 2
        ambiguous = next(c for c in doc["cases"] if c["oracle"]["clarification_requires_material_discriminator"])
        empty_clarification = {
            "id": ambiguous["id"], "next_step": "CLARIFY",
            "handoff_literal": ambiguous["literal_request"],
            "request_sha256": sha(ambiguous["literal_request"]),
            "router_effect_authorized": False,
            "clarification_question": "¿Cuál?",
        }
        if not check_result(ambiguous, empty_clarification):
            print(json.dumps({"status": "SELF_TEST_EMPTY_CLARIFICATION_FALSE_PASS"}))
            return 2
        print(json.dumps({"status": "SELF_TEST_VALIDATOR_NEGATIVES_PASS",
                          "negative_probes": len(probes) + 3, "stats": stats}, ensure_ascii=False))
        return 0
    if args.responses is None:
        print(json.dumps({"status": "CORPUS_VALID_NOT_EXECUTED",
                          "checkpoint_done": False, "stats": stats}, ensure_ascii=False))
        return 0
    results = json.loads(args.responses.read_text(encoding="utf-8"))
    if not isinstance(results, list):
        print(json.dumps({"status": "FAIL", "errors": ["RESPONSES_NOT_ARRAY"]}))
        return 2
    indexes = [r.get("id") for r in results if isinstance(r, dict)]
    if len(indexes) != len(results) or len(indexes) != len(set(indexes)):
        print(json.dumps({"status": "FAIL", "errors": ["DUPLICATED_OR_INVALID_RESPONSE_IDS"]}))
        return 2
    by_id = {r["id"]: r for r in results}
    expected = {x["id"] for x in doc["cases"]}
    extra = sorted(by_id.keys() - expected)
    missing = sorted(expected - by_id.keys())
    issues = [f"MISSING:{x}" for x in missing] + [f"UNDECLARED:{x}" for x in extra]
    for case in doc["cases"]:
        if case["id"] in by_id:
            issues.extend(check_result(case, by_id[case["id"]]))
    print(json.dumps({"status": "PROBE_FAIL" if issues else "PROBE_CONTRACT_SHAPE_PASS_UNATTESTED",
                      "requires_independent_source_and_consumer_attestation": True,
                      "not_a_checkpoint_closure": True,
                      "tested": len(expected) - len(missing), "errors": issues,
                      "stats": stats}, ensure_ascii=False))
    return 2 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
