#!/usr/bin/env python3
import argparse
import copy
import json
from pathlib import Path
from typing import Any, Dict, List

CONTRACT_DEFAULT = Path(__file__).resolve().parents[1] / "contratos" / "s30_self_governance_gate_v1.json"


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _truthy_status(v: Any) -> bool:
    if v is True:
        return True
    if isinstance(v, str):
        return v.upper() in {"PASS", "PROVEN", "CONFIRMED", "RESOLVED", "NOT_REQUIRED_WITH_REASON"}
    if isinstance(v, dict):
        return _truthy_status(v.get("status"))
    return False


def evaluate(contract: Dict[str, Any], receipt: Dict[str, Any]) -> Dict[str, Any]:
    failed_checks: List[str] = []
    hard_guard_failures: List[str] = []
    blocker_failures: List[str] = []
    sequence_failures: List[str] = []

    if receipt.get("base_main_sha") != contract.get("base_main_sha"):
        failed_checks.append("BASE_MAIN_SHA_MISMATCH")

    required_sequence = contract["mandatory_sequence"][:-1]
    resolved_sequence = receipt.get("sequence_resolution") or {}
    for step in required_sequence:
        if not _truthy_status(resolved_sequence.get(step)):
            sequence_failures.append(step)

    preflight = contract["cheap_preflight"]
    required_checks = preflight["checks"]
    observed_checks = receipt.get("preflight_checks") or {}
    for check in required_checks:
        observed = observed_checks.get(check)
        if not _truthy_status(observed):
            failed_checks.append(check)
            continue
        requirement = (preflight.get("check_requirements") or {}).get(check) or {}
        required_subproofs = requirement.get("required_subproofs") or []
        if required_subproofs:
            resolved = observed.get("resolved") if isinstance(observed, dict) else None
            resolved_set = set(resolved) if isinstance(resolved, list) else set()
            for subproof in required_subproofs:
                if subproof not in resolved_set:
                    failed_checks.append(f"{check}:{subproof}")

    frontier = receipt.get("frontier")
    if not isinstance(frontier, dict):
        blocker_failures.append("FRONTIER_MISSING_OR_NOT_OBJECT")
    else:
        for field in contract["frontier_contract"]["required_fields"]:
            if field not in frontier:
                blocker_failures.append(f"FRONTIER_FIELD_MISSING:{field}")
        blockers = frontier.get("blockers") or []
        required_blocker_fields = contract["blocker_contract"]["required_fields"]
        for idx, blocker in enumerate(blockers):
            if not isinstance(blocker, dict):
                blocker_failures.append(f"BLOCKER_NOT_OBJECT:{idx}")
                continue
            for field in required_blocker_fields:
                if field not in blocker:
                    blocker_failures.append(f"BLOCKER_FIELD_MISSING:{idx}:{field}")

    for idx, candidate in enumerate(receipt.get("hard_guard_candidates") or []):
        triggers = set(candidate.get("triggers") or [])
        must_promote = bool(triggers.intersection(contract["hard_guard_promotion"]["trigger_any"]))
        if not must_promote:
            continue
        closure = candidate.get("closure") or {}
        for required in contract["hard_guard_promotion"]["required_closure"]:
            if not _truthy_status(closure.get(required)):
                hard_guard_failures.append(f"{idx}:{candidate.get('ekb_code','UNKNOWN')}:{required}")

    safety = receipt.get("safety_readback") or {}
    for key in ("runtime_changed", "production_changed", "main_merged", "scheduler_changed", "s26_mutated"):
        if safety.get(key) is not False:
            failed_checks.append(f"SAFETY_READBACK:{key}")

    all_failures = sequence_failures + failed_checks + hard_guard_failures + blocker_failures
    if all_failures:
        first_bad = (
            f"SEQUENCE:{sequence_failures[0]}" if sequence_failures else
            f"PREFLIGHT:{failed_checks[0]}" if failed_checks else
            f"HARD_GUARD:{hard_guard_failures[0]}" if hard_guard_failures else
            f"BLOCKER_CONTRACT:{blocker_failures[0]}"
        )
        return {
            "result": preflight["failure_action"],
            "first_bad_hop": first_bad,
            "material_work_allowed": False,
            "sequence_failures": sequence_failures,
            "failed_checks": failed_checks,
            "hard_guard_failures": hard_guard_failures,
            "blocker_failures": blocker_failures,
            "claim_ceiling": "SELF_GOVERNANCE_PREEXECUTION_ASSURANCE_BLOCKED"
        }

    return {
        "result": "PASS_TO_MATERIAL_WORK",
        "first_bad_hop": None,
        "material_work_allowed": True,
        "sequence_failures": [],
        "failed_checks": [],
        "hard_guard_failures": [],
        "blocker_failures": [],
        "claim_ceiling": contract["claim_ceiling"]
    }


def _positive_fixture(contract: Dict[str, Any]) -> Dict[str, Any]:
    seq = {
        key: {"status": "PROVEN", "evidence": f"selftest:{key}"}
        for key in contract["mandatory_sequence"][:-1]
    }
    requirements = contract["cheap_preflight"].get("check_requirements") or {}
    checks: Dict[str, Any] = {}
    for key in contract["cheap_preflight"]["checks"]:
        check = {"status": "PASS", "evidence": f"selftest:{key}"}
        required_subproofs = (requirements.get(key) or {}).get("required_subproofs") or []
        if required_subproofs:
            check["resolved"] = list(required_subproofs)
        checks[key] = check

    return {
        "receipt_version": "v0.2",
        "lane": "S30-A",
        "owner": "S30",
        "base_main_sha": contract["base_main_sha"],
        "intended_material_action": "GIT_WRITE",
        "sequence_resolution": seq,
        "preflight_checks": checks,
        "frontier": {
            "current_stage": "S30-A_SELF_GOVERNANCE_PREEXECUTION_ASSURANCE",
            "next_gate": "CI_EXACT_HEAD_SELF_GOVERNANCE_WIRING",
            "blockers": [{
                "code": "EXAMPLE_CAUSAL_BLOCKER",
                "affected_scope": "CANONICAL_SUPABASE_RECONCILIATION",
                "causal_gate": "EXAMPLE_GATE",
                "owner": "S30",
                "independent_safe_work": ["GITHUB_SELF_GOVERNANCE_GATE"],
                "invalidation_condition": "gate becomes proven"
            }],
            "safe_parallel_work": ["GITHUB_SELF_GOVERNANCE_GATE"]
        },
        "hard_guard_candidates": [{
            "ekb_code": "DB-001",
            "triggers": ["RECURRENT", "MACHINE_DETECTABLE"],
            "closure": {
                key: {"status": "PASS"}
                for key in contract["hard_guard_promotion"]["required_closure"]
            }
        }],
        "safety_readback": {
            "runtime_changed": False,
            "production_changed": False,
            "main_merged": False,
            "scheduler_changed": False,
            "s26_mutated": False
        },
        "evidence": {"mode": "SELFTEST"}
    }


def self_test(contract: Dict[str, Any]) -> Dict[str, Any]:
    positive = _positive_fixture(contract)
    pos = evaluate(contract, positive)
    assert pos["result"] == "PASS_TO_MATERIAL_WORK" and pos["material_work_allowed"] is True

    missing = copy.deepcopy(positive)
    missing["preflight_checks"].pop("IMPORT_CLOSURE")
    neg_missing = evaluate(contract, missing)
    assert neg_missing["result"] == "FAIL_CLOSED_BEFORE_MATERIAL_WORK"
    assert neg_missing["material_work_allowed"] is False
    assert "IMPORT_CLOSURE" in neg_missing["failed_checks"]

    sql_signature = copy.deepcopy(positive)
    resolved = sql_signature["preflight_checks"]["SCHEMA_AND_CONSTRAINTS_RESOLVED"]["resolved"]
    resolved.remove("DEPENDENT_SQL_FUNCTION_SIGNATURES")
    neg_sql_signature = evaluate(contract, sql_signature)
    assert neg_sql_signature["result"] == "FAIL_CLOSED_BEFORE_MATERIAL_WORK"
    assert neg_sql_signature["material_work_allowed"] is False
    assert "SCHEMA_AND_CONSTRAINTS_RESOLVED:DEPENDENT_SQL_FUNCTION_SIGNATURES" in neg_sql_signature["failed_checks"]

    text_only = copy.deepcopy(positive)
    text_only["hard_guard_candidates"][0]["closure"] = {"EKB_UPDATED": {"status": "PASS"}}
    neg_text = evaluate(contract, text_only)
    assert neg_text["result"] == "FAIL_CLOSED_BEFORE_MATERIAL_WORK"
    assert neg_text["material_work_allowed"] is False
    assert any("DETECTOR_IMPLEMENTED" in item for item in neg_text["hard_guard_failures"])

    return {
        "status": "PASS",
        "cases": {
            "positive_equivalent": pos["result"],
            "negative_missing_preflight": neg_missing["result"],
            "negative_unresolved_sql_function_signature": neg_sql_signature["result"],
            "negative_text_only_ekb": neg_text["result"]
        }
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", default=str(CONTRACT_DEFAULT))
    parser.add_argument("--input")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    contract = load_json(Path(args.contract))
    outputs: Dict[str, Any] = {}
    if args.self_test:
        outputs["self_test"] = self_test(contract)
    if args.input:
        outputs["evaluation"] = evaluate(contract, load_json(Path(args.input)))
    if not outputs:
        parser.error("provide --self-test and/or --input")
    print(json.dumps(outputs, indent=2, sort_keys=True))
    if "evaluation" in outputs and outputs["evaluation"]["result"] != "PASS_TO_MATERIAL_WORK":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
