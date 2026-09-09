#!/usr/bin/env python3
"""Deterministic S26-E applicability/Card fallback pre-execution gate.

The gate consumes evidence-bound readbacks. It computes EKB applicability from the
observed lifecycle phase, validates Card discovery provenance, requires every
structural fallback to be explicitly evaluated, and returns non-zero for any
manual/blocked decision when invoked as an execution gate.
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

CARD_CONTRACT_REQUIRED_BEFORE = {
    "ekb_readback_present",
    "ekb_applicability_resolved",
    "card_resolution_readback_present",
    "governed_fallback_readback_if_no_card",
    "s26_e_pre_execution_gate_pass",
}
CARD_CONTRACT_REQUIRED_BLOCKED = {
    "missing_ekb_readback",
    "unresolved_ekb_applicability",
    "missing_card_resolution_readback",
    "no_card_direct_manual_without_structural_fallback",
    "critical_card_ambiguity",
    "schema_invention",
    "data_model_mutation_for_ui",
    "missing_s26_e_pre_execution_gate",
}
CARD_JUDGE_REQUIRED_PASS = {
    "ekb_readback_present",
    "ekb_applicability_resolved",
    "card_resolution_readback_present",
    "governed_fallback_readback_if_no_card",
    "s26_e_pre_execution_gate_pass",
}
CARD_JUDGE_REQUIRED_FAIL = set(CARD_CONTRACT_REQUIRED_BLOCKED)


def _block(code: str, *, learning_persistible: bool = False) -> dict[str, Any]:
    return {
        "decision": code,
        "material_execution_allowed": False,
        "card_resolution": None,
        "fallback_resolution": None,
        "learning_persistible": learning_persistible,
    }


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _learning_eligible(candidate: Any, contract: dict[str, Any]) -> bool:
    if not isinstance(candidate, dict) or candidate.get("verified") is not True:
        return False
    lp = contract["learning_persistence"]
    for field in lp["required_fields"]:
        value = candidate.get(field)
        if value in (None, "", [], {}):
            return False
    refs = candidate.get("evidence_refs")
    if not isinstance(refs, list) or not refs or not all(_nonempty_string(ref) for ref in refs):
        return False
    provenance = candidate.get("provenance")
    if not isinstance(provenance, dict):
        return False
    return all(_nonempty_string(provenance.get(field)) for field in lp["provenance_required_fields"])


def _parse_top_level_lists(text: str) -> tuple[dict[str, str], dict[str, list[str]]]:
    scalars: dict[str, str] = {}
    lists: dict[str, list[str]] = {}
    current: str | None = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw == raw.lstrip() and ":" in raw:
            key, value = raw.split(":", 1)
            key = key.strip()
            value = value.strip()
            current = key
            if value:
                scalars[key] = value
            else:
                lists.setdefault(key, [])
            continue
        stripped = raw.strip()
        if current and stripped.startswith("- "):
            lists.setdefault(current, []).append(stripped[2:].strip())
    return scalars, lists


def validate_card_pre_execution_binding() -> None:
    failures: list[str] = []
    if not CARD_CONTRACT_PATH.exists():
        failures.append(f"contract:missing:{CARD_CONTRACT_PATH}")
    if not CARD_JUDGE_PATH.exists():
        failures.append(f"judge:missing:{CARD_JUDGE_PATH}")
    if failures:
        raise AssertionError("S26_E_CARD_BINDING_INVALID=" + "|".join(failures))

    contract_scalars, contract_lists = _parse_top_level_lists(CARD_CONTRACT_PATH.read_text(encoding="utf-8"))
    judge_scalars, judge_lists = _parse_top_level_lists(CARD_JUDGE_PATH.read_text(encoding="utf-8"))

    expected_contract = "S26-E-GOVERNED-APPLICABILITY-CARD-FALLBACK-v0.1"
    if contract_scalars.get("operation") != "CREACION_CARD_LF":
        failures.append("contract:wrong_operation")
    if judge_scalars.get("operation") != "CREACION_CARD_LF":
        failures.append("judge:wrong_operation")
    if contract_scalars.get("governance_pre_execution_contract") != expected_contract:
        failures.append("contract:wrong_governance_binding")
    if judge_scalars.get("governance_pre_execution_contract") != expected_contract:
        failures.append("judge:wrong_governance_binding")

    missing = CARD_CONTRACT_REQUIRED_BEFORE - set(contract_lists.get("required_before_write", []))
    failures.extend(f"contract:required_before_write:{item}" for item in sorted(missing))
    missing = CARD_CONTRACT_REQUIRED_BLOCKED - set(contract_lists.get("blocked", []))
    failures.extend(f"contract:blocked:{item}" for item in sorted(missing))
    missing = CARD_JUDGE_REQUIRED_PASS - set(judge_lists.get("pass_if", []))
    failures.extend(f"judge:pass_if:{item}" for item in sorted(missing))
    missing = CARD_JUDGE_REQUIRED_FAIL - set(judge_lists.get("fail_if", []))
    failures.extend(f"judge:fail_if:{item}" for item in sorted(missing))

    if failures:
        raise AssertionError("S26_E_CARD_BINDING_INVALID=" + "|".join(failures))
    print("S26_E_CARD_PRE_EXECUTION_BINDING=PASS")


def _normalize_severity(value: Any, contract: dict[str, Any]) -> str:
    normalized = str(value or "").strip().upper()
    for canonical, aliases in contract["ekb"]["severity_aliases"].items():
        if normalized in {str(alias).strip().upper() for alias in aliases}:
            return canonical
    return normalized


def _validate_context(payload: dict[str, Any], contract: dict[str, Any]) -> dict[str, str] | None:
    context = payload.get("applicability_context")
    if not isinstance(context, dict):
        return None
    result: dict[str, str] = {}
    for field in contract["applicability_context"]["required_fields"]:
        value = context.get(field)
        if not _nonempty_string(value):
            return None
        result[field] = value.strip()
    return result


def _computed_rule_applicability(rule: dict[str, Any], context: dict[str, str], contract: dict[str, Any]) -> bool:
    phase = str(rule["lifecycle_phase"]).strip().upper()
    context_phase = context["lifecycle_phase"].strip().upper()
    global_tokens = {token.upper() for token in contract["applicability_context"]["global_tokens"]}
    return phase in global_tokens or phase == context_phase


def _valid_card_candidate(candidate: Any, contract: dict[str, Any]) -> bool:
    if not isinstance(candidate, dict):
        return False
    for field in contract["card_resolution"]["candidate_required_fields"]:
        if field not in candidate:
            return False
    if not _nonempty_string(candidate.get("card_code")):
        return False
    if candidate.get("match") not in contract["card_resolution"]["match_values"]:
        return False
    provenance = candidate.get("provenance")
    if not isinstance(provenance, dict):
        return False
    return all(
        _nonempty_string(provenance.get(field))
        for field in contract["card_resolution"]["candidate_provenance_required_fields"]
    )


def _valid_fallback_check(check: Any, contract: dict[str, Any]) -> bool:
    if not isinstance(check, dict):
        return False
    required = contract["fallback_rules"]["check_required_fields"]
    if not all(field in check for field in required):
        return False
    for field in contract["fallback_rules"]["explicit_boolean_fields"]:
        if type(check.get(field)) is not bool:
            return False
    if not _nonempty_string(check.get("evidence_ref")):
        return False
    if check["available"] is False and check["safe"] is True:
        return False
    return True


def evaluate(payload: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    learning_persistible = _learning_eligible(payload.get("learning_candidate"), contract)

    if payload.get("router_status") != "READY_TO_EXECUTE":
        return _block("BLOCKED_ROUTER", learning_persistible=learning_persistible)

    context = _validate_context(payload, contract)
    if context is None:
        return _block("BLOCKED_APPLICABILITY_CONTEXT_MISSING", learning_persistible=learning_persistible)

    if payload.get("ekb_readback_present") is not True:
        return _block("BLOCKED_EKB_READBACK_MISSING", learning_persistible=learning_persistible)

    rules = payload.get("ekb_rules")
    if not isinstance(rules, list):
        return _block("BLOCKED_EKB_READBACK_INVALID", learning_persistible=learning_persistible)

    normalized_rules: list[dict[str, Any]] = []
    for rule in rules:
        if not isinstance(rule, dict):
            return _block("BLOCKED_EKB_READBACK_INVALID", learning_persistible=learning_persistible)
        required = contract["ekb"]["rule_required_fields"]
        if not all(field in rule for field in required):
            return _block("BLOCKED_EKB_READBACK_INVALID", learning_persistible=learning_persistible)
        if not _nonempty_string(rule.get("rule_id")) or not _nonempty_string(rule.get("lifecycle_phase")):
            return _block("BLOCKED_EKB_READBACK_INVALID", learning_persistible=learning_persistible)
        if type(rule.get("applicable")) is not bool or type(rule.get("control_mapped")) is not bool:
            return _block("BLOCKED_EKB_READBACK_INVALID", learning_persistible=learning_persistible)
        conflicts = rule.get("conflicts_with", [])
        if not isinstance(conflicts, list) or not all(_nonempty_string(item) for item in conflicts):
            return _block("BLOCKED_EKB_READBACK_INVALID", learning_persistible=learning_persistible)

        computed = _computed_rule_applicability(rule, context, contract)
        if rule["applicable"] is not computed:
            return _block("BLOCKED_EKB_APPLICABILITY_MISMATCH", learning_persistible=learning_persistible)

        normalized = dict(rule)
        normalized["_computed_applicable"] = computed
        normalized["_severity"] = _normalize_severity(rule.get("severity"), contract)
        normalized_rules.append(normalized)

    applicable = [rule for rule in normalized_rules if rule["_computed_applicable"]]
    applicable_ids = {str(rule["rule_id"]) for rule in applicable}

    for rule in applicable:
        if rule["_severity"] in {"HIGH", "CRITICAL"} and rule.get("control_mapped") is not True:
            return _block("BLOCKED_UNMAPPED_HIGH_CRITICAL_RULE", learning_persistible=learning_persistible)
        conflicts = rule.get("conflicts_with", [])
        if any(str(other) in applicable_ids for other in conflicts):
            return _block("BLOCKED_CONTRADICTORY_APPLICABLE_RULES", learning_persistible=learning_persistible)

    if payload.get("card_readback_present") is not True:
        return _block("BLOCKED_CARD_READBACK_MISSING", learning_persistible=learning_persistible)

    cards = payload.get("card_candidates")
    if not isinstance(cards, list):
        return _block("BLOCKED_CARD_READBACK_INVALID", learning_persistible=learning_persistible)
    if not all(_valid_card_candidate(card, contract) for card in cards):
        return _block("BLOCKED_CARD_READBACK_INVALID", learning_persistible=learning_persistible)

    exact = [card for card in cards if card["match"] == "EXACT"]
    compatible = [card for card in cards if card["match"] == "COMPATIBLE"]

    if len(exact) > 1 or (not exact and len(compatible) > 1):
        return _block("BLOCKED_CARD_AMBIGUOUS", learning_persistible=learning_persistible)

    if len(exact) == 1:
        return {
            "decision": "READY_TO_EXECUTE",
            "material_execution_allowed": True,
            "card_resolution": {"state": "EXACT", "card_code": exact[0]["card_code"]},
            "fallback_resolution": None,
            "learning_persistible": learning_persistible,
        }

    if len(compatible) == 1:
        return {
            "decision": "READY_TO_EXECUTE",
            "material_execution_allowed": True,
            "card_resolution": {"state": "COMPATIBLE", "card_code": compatible[0]["card_code"]},
            "fallback_resolution": None,
            "learning_persistible": learning_persistible,
        }

    checks = payload.get("fallback_checks")
    if not isinstance(checks, dict) or any(name not in checks for name in STRUCTURAL_FALLBACKS):
        return _block("BLOCKED_UNSAFE_FALLBACK", learning_persistible=learning_persistible)

    for name in STRUCTURAL_FALLBACKS:
        check = checks[name]
        if not _valid_fallback_check(check, contract):
            return _block("BLOCKED_UNSAFE_FALLBACK", learning_persistible=learning_persistible)
        if check["available"] and check["schema_invented"]:
            return _block("BLOCKED_SCHEMA_INVENTION", learning_persistible=learning_persistible)
        if check["available"] and check["data_model_mutation"]:
            return _block("BLOCKED_DATA_MODEL_MUTATION", learning_persistible=learning_persistible)
        if check["available"] and check["safe"]:
            return {
                "decision": "READY_TO_EXECUTE",
                "material_execution_allowed": True,
                "card_resolution": {"state": "NONE", "card_code": None},
                "fallback_resolution": name,
                "learning_persistible": learning_persistible,
            }

    manual_reason = payload.get("manual_reason")
    if not _nonempty_string(manual_reason):
        return _block("BLOCKED_UNSAFE_FALLBACK", learning_persistible=learning_persistible)

    return {
        "decision": "MANUAL_REQUIRED",
        "material_execution_allowed": False,
        "card_resolution": {"state": "NONE", "card_code": None},
        "fallback_resolution": "MANUAL",
        "learning_persistible": learning_persistible,
    }


def gate_exit_code(result: dict[str, Any]) -> int:
    return 0 if result.get("decision") == "READY_TO_EXECUTE" and result.get("material_execution_allowed") is True else 3


def run_cases(path: Path, contract: dict[str, Any]) -> int:
    validate_card_pre_execution_binding()
    data = json.loads(path.read_text(encoding="utf-8"))
    cases = data.get("cases", [])
    if not cases:
        raise AssertionError("S26_E_CASES_MISSING")
    failures: list[str] = []
    ready_exit_seen = False
    blocked_exit_seen = False
    for case in cases:
        result = evaluate(case["input"], contract)
        expected = case["expected"]
        for key, expected_value in expected.items():
            if result.get(key) != expected_value:
                failures.append(
                    f"{case['id']}:{key}: expected={expected_value!r} actual={result.get(key)!r}"
                )
        exit_code = gate_exit_code(result)
        expected_exit = case.get("expected_exit_code", 0 if expected.get("decision") == "READY_TO_EXECUTE" else 3)
        if exit_code != expected_exit:
            failures.append(f"{case['id']}:exit_code: expected={expected_exit} actual={exit_code}")
        ready_exit_seen = ready_exit_seen or exit_code == 0
        blocked_exit_seen = blocked_exit_seen or exit_code != 0

    if not ready_exit_seen:
        failures.append("suite:missing_ready_exit_code_0_case")
    if not blocked_exit_seen:
        failures.append("suite:missing_nonzero_block_case")

    print(f"S26_E_CASE_COUNT={len(cases)}")
    print(f"S26_E_FAILURE_COUNT={len(failures)}")
    for failure in failures:
        print(f"FAIL={failure}")
    if failures:
        return 1
    print("S26_E_CLI_GATE=PASS ready=0 blocked_or_manual=3")
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
        return run_cases(args.cases, contract)
    if args.input:
        payload = json.loads(args.input.read_text(encoding="utf-8"))
        result = evaluate(payload, contract)
        print(json.dumps(result, sort_keys=True))
        return gate_exit_code(result)
    parser.error("use --self-test or --input")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
