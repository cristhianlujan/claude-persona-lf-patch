#!/usr/bin/env python3
"""Deterministic S26-E applicability/Card fallback governance judge.

This judge is read-only. It does not resolve repository assets itself and does not
persist EKB. It validates the structured readbacks that MUST exist before material
execution and returns the governed decision. It also verifies that the candidate
Card creation contract/judge are explicitly bound to this pre-execution gate.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "gobernanza/contratos/s26_e_governed_applicability_card_fallback_v1.json"
CARD_CONTRACT_PATH = ROOT / "gobernanza/contratos/contrato_card_lf.yaml"
CARD_JUDGE_PATH = ROOT / "gobernanza/judges/judge_contrato_card_lf.yaml"
DEFAULT_CASES = ROOT / "sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_cases.json"

STRUCTURAL_FALLBACKS = (
    "EXISTING_CONTRACT_SCHEMA",
    "REUSABLE_GENERIC_CAPABILITY",
    "SAFE_COMPOSITION",
)

CARD_BINDING_REQUIRED = (
    "governance_pre_execution_contract: S26-E-GOVERNED-APPLICABILITY-CARD-FALLBACK-v0.1",
    "  - ekb_readback_present",
    "  - ekb_applicability_resolved",
    "  - card_resolution_readback_present",
    "  - governed_fallback_readback_if_no_card",
    "  - s26_e_pre_execution_gate_pass",
    "  - no_card_direct_manual_without_structural_fallback",
    "  - critical_card_ambiguity",
    "  - schema_invention",
    "  - data_model_mutation_for_ui",
)


def _block(code: str, *, learning_persistible: bool = False) -> dict[str, Any]:
    return {
        "decision": code,
        "material_execution_allowed": False,
        "card_resolution": None,
        "fallback_resolution": None,
        "learning_persistible": learning_persistible,
    }


def _learning_eligible(candidate: Any, contract: dict[str, Any]) -> bool:
    if not isinstance(candidate, dict):
        return False
    lp = contract["learning_persistence"]
    if candidate.get("verified") is not True:
        return False
    for field in lp["required_fields"]:
        value = candidate.get(field)
        if value in (None, "", [], {}):
            return False
    provenance = candidate.get("provenance")
    if not isinstance(provenance, dict):
        return False
    return all(provenance.get(field) not in (None, "") for field in lp["provenance_required_fields"])


def validate_card_pre_execution_binding() -> None:
    failures: list[str] = []
    for path, label in ((CARD_CONTRACT_PATH, "contract"), (CARD_JUDGE_PATH, "judge")):
        if not path.exists():
            failures.append(f"{label}:missing:{path}")
            continue
        text = path.read_text(encoding="utf-8")
        for required in CARD_BINDING_REQUIRED:
            if required not in text:
                failures.append(f"{label}:missing_binding:{required.strip()}")
    if failures:
        raise AssertionError("S26_E_CARD_BINDING_INVALID=" + "|".join(failures))
    print("S26_E_CARD_PRE_EXECUTION_BINDING=PASS")


def evaluate(payload: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    learning_persistible = _learning_eligible(payload.get("learning_candidate"), contract)

    if payload.get("router_status") != "READY_TO_EXECUTE":
        return _block("BLOCKED_ROUTER", learning_persistible=learning_persistible)

    if payload.get("ekb_readback_present") is not True:
        return _block("BLOCKED_EKB_READBACK_MISSING", learning_persistible=learning_persistible)

    rules = payload.get("ekb_rules")
    if not isinstance(rules, list):
        return _block("BLOCKED_EKB_READBACK_MISSING", learning_persistible=learning_persistible)

    applicable = [rule for rule in rules if isinstance(rule, dict) and rule.get("applicable") is True]
    applicable_ids = {str(rule.get("rule_id")) for rule in applicable if rule.get("rule_id")}

    for rule in applicable:
        if not all(key in rule for key in contract["ekb"]["applicable_rule_required_fields"]):
            return _block("BLOCKED_EKB_READBACK_MISSING", learning_persistible=learning_persistible)
        severity = str(rule.get("severity", "")).upper()
        if severity in {"HIGH", "CRITICAL"} and rule.get("control_mapped") is not True:
            return _block("BLOCKED_UNMAPPED_HIGH_CRITICAL_RULE", learning_persistible=learning_persistible)
        conflicts = rule.get("conflicts_with", [])
        if any(str(other) in applicable_ids for other in conflicts):
            return _block("BLOCKED_CONTRADICTORY_APPLICABLE_RULES", learning_persistible=learning_persistible)

    cards = payload.get("card_candidates")
    if not isinstance(cards, list):
        cards = []
    exact = [c for c in cards if isinstance(c, dict) and c.get("match") == "EXACT"]
    compatible = [c for c in cards if isinstance(c, dict) and c.get("match") == "COMPATIBLE"]

    if len(exact) > 1 or (not exact and len(compatible) > 1):
        return _block("BLOCKED_CARD_AMBIGUOUS", learning_persistible=learning_persistible)

    if len(exact) == 1:
        return {
            "decision": "READY_TO_EXECUTE",
            "material_execution_allowed": True,
            "card_resolution": {"state": "EXACT", "card_code": exact[0].get("card_code")},
            "fallback_resolution": None,
            "learning_persistible": learning_persistible,
        }

    if len(compatible) == 1:
        return {
            "decision": "READY_TO_EXECUTE",
            "material_execution_allowed": True,
            "card_resolution": {"state": "COMPATIBLE", "card_code": compatible[0].get("card_code")},
            "fallback_resolution": None,
            "learning_persistible": learning_persistible,
        }

    checks = payload.get("fallback_checks")
    if not isinstance(checks, dict) or any(name not in checks for name in STRUCTURAL_FALLBACKS):
        return _block("BLOCKED_UNSAFE_FALLBACK", learning_persistible=learning_persistible)

    for name in STRUCTURAL_FALLBACKS:
        check = checks[name]
        if not isinstance(check, dict):
            return _block("BLOCKED_UNSAFE_FALLBACK", learning_persistible=learning_persistible)
        if check.get("available") is True and check.get("schema_invented") is True:
            return _block("BLOCKED_SCHEMA_INVENTION", learning_persistible=learning_persistible)
        if check.get("available") is True and check.get("data_model_mutation") is True:
            return _block("BLOCKED_DATA_MODEL_MUTATION", learning_persistible=learning_persistible)
        if check.get("available") is True and check.get("safe") is True:
            return {
                "decision": "READY_TO_EXECUTE",
                "material_execution_allowed": True,
                "card_resolution": {"state": "NONE", "card_code": None},
                "fallback_resolution": name,
                "learning_persistible": learning_persistible,
            }

    manual_reason = payload.get("manual_reason")
    if not isinstance(manual_reason, str) or not manual_reason.strip():
        return _block("BLOCKED_UNSAFE_FALLBACK", learning_persistible=learning_persistible)

    return {
        "decision": "MANUAL_REQUIRED",
        "material_execution_allowed": False,
        "card_resolution": {"state": "NONE", "card_code": None},
        "fallback_resolution": "MANUAL",
        "learning_persistible": learning_persistible,
    }


def run_cases(path: Path, contract: dict[str, Any]) -> int:
    validate_card_pre_execution_binding()
    data = json.loads(path.read_text(encoding="utf-8"))
    cases = data.get("cases", [])
    if not cases:
        raise AssertionError("S26_E_CASES_MISSING")
    failures: list[str] = []
    for case in cases:
        result = evaluate(case["input"], contract)
        expected = case["expected"]
        for key, expected_value in expected.items():
            if result.get(key) != expected_value:
                failures.append(
                    f"{case['id']}:{key}: expected={expected_value!r} actual={result.get(key)!r}"
                )
    print(f"S26_E_CASE_COUNT={len(cases)}")
    print(f"S26_E_FAILURE_COUNT={len(failures)}")
    for failure in failures:
        print(f"FAIL={failure}")
    if failures:
        return 1
    print("S26_E_GOVERNANCE=PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--input", type=Path)
    args = parser.parse_args()

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("contract_code") != "S26-E-GOVERNED-APPLICABILITY-CARD-FALLBACK-v0.1":
        raise AssertionError("S26_E_CONTRACT_CODE_INVALID")

    validate_card_pre_execution_binding()
    if args.self_test:
        data = json.loads(args.cases.read_text(encoding="utf-8"))
        cases = data.get("cases", [])
        if not cases:
            raise AssertionError("S26_E_CASES_MISSING")
        failures: list[str] = []
        for case in cases:
            result = evaluate(case["input"], contract)
            expected = case["expected"]
            for key, expected_value in expected.items():
                if result.get(key) != expected_value:
                    failures.append(
                        f"{case['id']}:{key}: expected={expected_value!r} actual={result.get(key)!r}"
                    )
        print(f"S26_E_CASE_COUNT={len(cases)}")
        print(f"S26_E_FAILURE_COUNT={len(failures)}")
        for failure in failures:
            print(f"FAIL={failure}")
        if failures:
            return 1
        print("S26_E_GOVERNANCE=PASS")
        return 0
    if args.input:
        payload = json.loads(args.input.read_text(encoding="utf-8"))
        print(json.dumps(evaluate(payload, contract), sort_keys=True))
        return 0
    parser.error("use --self-test or --input")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
