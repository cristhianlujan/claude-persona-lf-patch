#!/usr/bin/env python3
"""SC-M2.5 candidate validator for STORY_IMPLEMENTATION_PACKAGE_V1_1.

This validator is structural only. It never replaces Story Pack A-Q judges,
Programming Utility judgment, transversal currentness/evidence authorities, or
runtime/orchestration controls.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

try:
    from jsonschema import Draft202012Validator
except ImportError as exc:  # fail closed: declared package dependency
    raise SystemExit("BLOCKED_DEPENDENCY_MISSING: jsonschema") from exc

HERE = Path(__file__).resolve().parent
SCHEMA_PATH = HERE / "story_implementation_package_v1.schema.json"
FORBIDDEN_RUNTIME_KEYS = {
    "work_protocol_manifest_v1",
    "work_protocol_runtime",
    "work_protocol_orchestrator",
    "g07_controller",
    "g08_closure_controller",
    "g09_cold_replay",
    "g10_final_closure_package",
    "g11_rollout",
}


def _schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def _walk_keys(value: Any) -> set[str]:
    out: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            out.add(str(key).lower())
            out.update(_walk_keys(child))
    elif isinstance(value, list):
        for child in value:
            out.update(_walk_keys(child))
    return out


def _path_overlap(allowed: list[str], protected: list[str]) -> bool:
    a = {x.rstrip("/") for x in allowed}
    p = {x.rstrip("/") for x in protected}
    if a & p:
        return True
    for left in a:
        for right in p:
            if left and right and (left.startswith(right + "/") or right.startswith(left + "/")):
                return True
    return False


def validate_package(package: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    validator = Draft202012Validator(_schema())
    for err in sorted(validator.iter_errors(package), key=lambda e: list(e.absolute_path)):
        loc = ".".join(str(x) for x in err.absolute_path) or "$"
        errors.append(f"SCHEMA:{loc}:{err.message}")

    # Do not run semantic structural invariants over malformed shapes.
    if errors:
        return errors

    keys = _walk_keys(package)
    forbidden = sorted(keys & FORBIDDEN_RUNTIME_KEYS)
    if forbidden:
        errors.append("WORK_PROTOCOL_REACTIVATION_FORBIDDEN:" + ",".join(forbidden))

    hb = package["hard_boundaries"]
    if _path_overlap(hb["allowed_path_patterns"], hb["protected_path_patterns"]):
        errors.append("HARD_BOUNDARY_PATH_COLLISION")

    closure = package["decision_closure"]
    blockers = package["blocked_if"]
    if closure["ready"]:
        if blockers:
            errors.append("FALSE_READY_WITH_BLOCKERS")
        if closure["open_decisions"]:
            errors.append("FALSE_READY_WITH_OPEN_DECISIONS")
        if closure["source_currentness_state"] != "PROVEN_CURRENT":
            errors.append("FALSE_READY_WITHOUT_CURRENT_SOURCE")
        if closure["evidence_completeness_state"] != "COMPLETE":
            errors.append("FALSE_READY_WITHOUT_COMPLETE_EVIDENCE")

    for pre in package["implementation_preconditions"]:
        if pre["state"] == "IMPLEMENTATION_PRECONDITION":
            if pre.get("design_effect") != "NONE":
                errors.append(f"PRECONDITION_MAY_CHANGE_DESIGN:{pre['precondition_code']}")
            if not pre.get("exact_resolver"):
                errors.append(f"PRECONDITION_RESOLVER_MISSING:{pre['precondition_code']}")
            if not pre.get("deterministic_resolution_rule"):
                errors.append(f"PRECONDITION_RULE_MISSING:{pre['precondition_code']}")
            if not pre.get("bounded_stage"):
                errors.append(f"PRECONDITION_STAGE_MISSING:{pre['precondition_code']}")
        if pre["state"] in {"SOURCE_CONFLICT", "PENDING_OWNER_DECISION", "PENDING_SOURCE_DEFINITION"}:
            if pre["blocking_scope"] == "NON_BLOCKING":
                errors.append(f"MATERIAL_PENDING_MARKED_NON_BLOCKING:{pre['precondition_code']}")

    reuse = package["task0_reuse_discovery"]
    cls = reuse["classification"]
    if cls == "CREATE_NEW":
        if not reuse["verified_absence"]:
            errors.append("CREATE_NEW_WITHOUT_VERIFIED_ABSENCE")
        if len(reuse["consumer_refs"]) < 2:
            errors.append("CREATE_NEW_WITH_FEWER_THAN_TWO_CONSUMERS")
        if reuse["owner_state"] != "RESOLVED":
            errors.append("CREATE_NEW_WITHOUT_OWNER")
        if reuse["candidate_assets"]:
            errors.append("CREATE_NEW_WITH_EXISTING_CANDIDATE")
    elif cls == "EXTEND_TRANSVERSAL":
        if reuse["owner_state"] != "RESOLVED":
            errors.append("EXTEND_TRANSVERSAL_OWNER_UNRESOLVED")
        if not reuse["owner_separation"]:
            errors.append("EXTEND_TRANSVERSAL_OWNER_SEPARATION_MISSING")
        if not reuse.get("selected_asset_ref"):
            errors.append("EXTEND_TRANSVERSAL_ASSET_MISSING")
    elif cls == "REUSE_AS_IS":
        if not reuse.get("selected_asset_ref"):
            errors.append("REUSE_AS_IS_ASSET_MISSING")
        if reuse["currentness_state"] != "PROVEN_CURRENT":
            errors.append("REUSE_AS_IS_CURRENTNESS_UNPROVEN")

    for decision in package["architecture_and_reuse_decisions"]:
        cls = decision["classification"]
        if cls in {"REUSE_AS_IS", "EXTEND_TRANSVERSAL"} and not decision.get("selected_asset_ref"):
            errors.append(f"REUSE_DECISION_ASSET_MISSING:{decision['need_code']}")
        if cls == "EXTEND_TRANSVERSAL" and decision["owner_state"] != "RESOLVED":
            errors.append(f"REUSE_DECISION_OWNER_UNRESOLVED:{decision['need_code']}")
        if cls == "CREATE_NEW" and len(decision["consumer_refs"]) < 2:
            errors.append(f"REUSE_DECISION_CREATE_NEW_CONSUMERS:{decision['need_code']}")

    return errors


def _valid_fixture() -> dict[str, Any]:
    h = "a" * 64
    return {
        "package_version": "STORY_IMPLEMENTATION_PACKAGE_V1_1",
        "canonical_evidence": "STORY_PACK_A_Q",
        "canonical_story_sha256": h,
        "source_refs": ["lf_eventos://19902", "story-pack://ONB_004"],
        "story_identity": {
            "story_code": "ONB_004",
            "module_code": "CLIENT_ONBOARDING",
            "screen_code": "ONB_004",
            "functional_unit_code": "NEW_CLIENT_DATA_COMPLETION",
            "source_version": "v1",
            "source_snapshot_sha256": "b" * 64,
        },
        "story_contracts": {
            "functional_contract": {},
            "design_system_contract": {},
            "field_validation_contract": {},
            "state_navigation_contract": {},
            "error_recovery_contract": {},
            "security_privacy_contract": {},
            "integration_contract": {},
            "story_test_obligations": {},
        },
        "outcome": {"result": "implement bounded ONB_004 task"},
        "architecture_and_reuse_decisions": [{
            "need_code": "STRUCTURED_OUTPUT",
            "classification": "REUSE_AS_IS",
            "selected_asset_ref": "PROFILE_STRUCTURED_OUTPUT_BOUNDARY",
            "owner_state": "RESOLVED",
            "currentness_state": "PROVEN_CURRENT",
            "consumer_refs": ["STORY_CREATOR", "PROGRAMMING_AGENT"],
            "evidence_refs": ["lf_activos://PROFILE_STRUCTURED_OUTPUT_BOUNDARY"],
            "rationale": "reuse existing boundary",
        }],
        "hard_boundaries": {
            "allowed_path_patterns": ["src/onboarding/**"],
            "protected_path_patterns": ["src/auth/**"],
            "allowed_effects": ["BOUNDED_WRITE"],
            "authorization_refs": ["story://ONB_004#authorized-scope"],
        },
        "implementation_preconditions": [{
            "precondition_code": "API_CLIENT_LOOKUP",
            "target_material": "existing API client",
            "state": "IMPLEMENTATION_PRECONDITION",
            "exact_resolver": "repo-search://existing-client",
            "expected_shape": "single existing client symbol",
            "deterministic_resolution_rule": "exactly one current candidate or BLOCKED",
            "bounded_stage": "before first integration edit",
            "evidence_required": ["exact path", "blob sha"],
            "blocking_scope": "TASK",
            "design_effect": "NONE",
        }],
        "context_transport": {
            "context_path_patterns": ["src/onboarding/**"],
            "max_context_bytes": 65536,
            "transport_ref": "Context Pack v2",
        },
        "wiring": {"consumer": "programacion.fn_agent_task_execution_bundle"},
        "implementation_delta_and_deliverables": {"mode": "bounded"},
        "executable_acceptance": {"cases": ["positive", "negative"]},
        "transition_and_rollback": {"required": false},
        "observability_and_evidence": {
            "evidence_refs": ["EVIDENCE_LEDGER://candidate"],
            "source_currentness_refs": ["CURRENTNESS_AUTHORITY://candidate"],
        },
        "decision_closure": {
            "ready": true,
            "ready_when": ["no material open decisions", "current source", "complete evidence"],
            "blocked_when": ["typed blocker present"],
            "open_decisions": [],
            "source_currentness_state": "PROVEN_CURRENT",
            "evidence_completeness_state": "COMPLETE",
        },
        "blocked_if": [],
        "task0_reuse_discovery": {
            "classification": "REUSE_AS_IS",
            "inventory_queries": ["public.lf_activos", "CONSUMER_BINDINGS"],
            "candidate_assets": ["PROFILE_STRUCTURED_OUTPUT_BOUNDARY"],
            "selected_asset_ref": "PROFILE_STRUCTURED_OUTPUT_BOUNDARY",
            "owner_state": "RESOLVED",
            "currentness_state": "PROVEN_CURRENT",
            "consumer_refs": ["STORY_CREATOR", "PROGRAMMING_AGENT"],
            "evidence_refs": ["lf_activos://PROFILE_STRUCTURED_OUTPUT_BOUNDARY"],
            "verified_absence": false,
            "owner_separation": true,
        },
        "task_views": [{
            "task_code": "ONB_004_UI",
            "task_class": "UI_IMPLEMENTATION",
            "selected_sections": ["outcome", "hard_boundaries", "story_contracts"],
            "max_context_bytes": 65536,
            "view_sha256": "c" * 64,
        }],
    }


def self_test() -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], str | None]] = []
    good = _valid_fixture()
    cases.append(("positive", good, None))

    def neg(name: str, mutate, expected: str) -> None:
        item = copy.deepcopy(good)
        mutate(item)
        cases.append((name, item, expected))

    neg("missing_sha", lambda p: p.pop("canonical_story_sha256"), "SCHEMA")
    neg("canonical_replaced", lambda p: p.__setitem__("canonical_evidence", "WORK_PROTOCOL"), "SCHEMA")
    neg("work_protocol_runtime_key", lambda p: p.__setitem__("work_protocol_runtime", {}), "SCHEMA")
    neg("path_collision", lambda p: p["hard_boundaries"]["protected_path_patterns"].append("src/onboarding/**"), "HARD_BOUNDARY_PATH_COLLISION")
    neg("ready_with_blocker", lambda p: p["blocked_if"].append({"code":"B1","state":"SOURCE_CONFLICT","affected_scope":"TASK","resolver_or_owner_ref":"owner://x"}), "FALSE_READY_WITH_BLOCKERS")
    neg("ready_with_open_decision", lambda p: p["decision_closure"]["open_decisions"].append("route choice"), "FALSE_READY_WITH_OPEN_DECISIONS")
    neg("stale_ready", lambda p: p["decision_closure"].__setitem__("source_currentness_state", "STALE"), "FALSE_READY_WITHOUT_CURRENT_SOURCE")
    neg("create_new_one_consumer", lambda p: p["task0_reuse_discovery"].update({"classification":"CREATE_NEW","candidate_assets":[],"selected_asset_ref":None,"verified_absence":True,"consumer_refs":["STORY_CREATOR"]}), "CREATE_NEW_WITH_FEWER_THAN_TWO_CONSUMERS")
    neg("extend_owner_unresolved", lambda p: p["task0_reuse_discovery"].update({"classification":"EXTEND_TRANSVERSAL","owner_state":"UNRESOLVED"}), "EXTEND_TRANSVERSAL_OWNER_UNRESOLVED")
    neg("precondition_without_resolver", lambda p: p["implementation_preconditions"][0].__setitem__("exact_resolver", None), "PRECONDITION_RESOLVER_MISSING")

    results = []
    passed = 0
    for name, payload, expected in cases:
        errs = validate_package(payload)
        if expected is None:
            ok = not errs
        else:
            ok = any(expected in err for err in errs)
        passed += int(ok)
        results.append({"case": name, "expected": expected or "PASS", "ok": ok, "errors": errs})

    return {
        "schema": "SC_M2_5_SELF_TEST_V1",
        "cases_total": len(results),
        "cases_passed": passed,
        "result": "PASS" if passed == len(results) else "FAIL",
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", nargs="?")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        result = self_test()
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0 if result["result"] == "PASS" else 1

    if not args.package:
        parser.error("package path required unless --self-test is used")
    payload = json.loads(Path(args.package).read_text(encoding="utf-8"))
    errors = validate_package(payload)
    result = {"result": "PASS" if not errors else "BLOCKED", "errors": errors}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
