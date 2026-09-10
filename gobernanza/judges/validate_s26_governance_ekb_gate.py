#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

CONTRACT_DEFAULT = Path(__file__).resolve().parents[1] / "contratos" / "s26_governance_ekb_card_fallback_v1.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _present(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def evaluate(contract: dict[str, Any], receipt: dict[str, Any]) -> dict[str, Any]:
    blockers: list[str] = []
    warnings: list[str] = []

    pre = receipt.get("pre_ekb_contract") or {}
    expected_pre = contract["existing_pre_ekb_contract"]
    if pre.get("contract_code") != expected_pre["contract_code"] or pre.get("status") != expected_pre["required_status"]:
        blockers.append("PRE_EKB_CONTRACT_NOT_ACTIVE")

    sequence = receipt.get("sequence") or []
    required_sequence = contract["mandatory_sequence"]
    if sequence != required_sequence:
        blockers.append("MANDATORY_SEQUENCE_NOT_PROVEN")
    if receipt.get("execution_started_before_gate") is not False:
        blockers.append("EXECUTION_STARTED_BEFORE_PREEXECUTION_GATE")

    applicability = receipt.get("applicability") or {}
    if applicability.get("critical_ambiguity") is True:
        blockers.append("CRITICAL_APPLICABILITY_AMBIGUITY")
    if applicability.get("status") not in contract["applicability"]["allowed"]:
        blockers.append("APPLICABILITY_UNRESOLVED")
    if applicability.get("status") == "NOT_APPLICABLE" and not _present(applicability.get("reason")):
        blockers.append("NOT_APPLICABLE_REASON_MISSING")

    readback = receipt.get("ekb_readback") or {}
    if readback.get("performed") is not True or not readback.get("source_refs") or not _present(readback.get("snapshot_digest")):
        blockers.append("EKB_READBACK_INCOMPLETE")

    rules = receipt.get("ekb_rules") or []
    applicable_controls: list[str] = []
    for idx, rule in enumerate(rules):
        state = rule.get("applicability")
        if state not in contract["applicability"]["allowed"]:
            blockers.append(f"EKB_RULE_APPLICABILITY_UNRESOLVED:{idx}")
            continue
        if state == "NOT_APPLICABLE":
            if not _present(rule.get("reason")):
                blockers.append(f"EKB_RULE_NA_REASON_MISSING:{idx}")
            continue
        control_ref = rule.get("control_ref")
        severity = str(rule.get("severity", "")).upper()
        if not _present(control_ref):
            blockers.append(f"APPLICABLE_EKB_RULE_WITHOUT_CONTROL:{idx}")
            if severity in {"HIGH", "CRITICAL"}:
                blockers.append(f"UNHANDLED_HIGH_CRITICAL_EKB_RULE:{idx}")
        else:
            applicable_controls.append(str(control_ref))

    contradictions = receipt.get("ekb_contradictions") or []
    for idx, contradiction in enumerate(contradictions):
        if contradiction.get("status") != "RESOLVED" or not _present(contradiction.get("resolution_ref")):
            blockers.append(f"EKB_CONTRADICTION_UNRESOLVED:{idx}")

    schema_policy = receipt.get("schema_policy") or {}
    if schema_policy.get("schema_invented") is not False:
        blockers.append("SCHEMA_INVENTION_FORBIDDEN")
    if schema_policy.get("data_model_mutated_to_fit_surface") is not False:
        blockers.append("DATA_MODEL_MUTATION_FORBIDDEN")

    card = receipt.get("card_resolution") or {}
    card_state = card.get("state")
    if card_state not in contract["card_resolution"]["states"]:
        blockers.append("CARD_STATE_INVALID")
    elif card_state == "AMBIGUOUS":
        blockers.append("CARD_AMBIGUOUS_FAIL_CLOSED")
    elif card_state == "EXACT":
        selected_card = card.get("selected_card_ref")
        candidates = card.get("candidate_refs") or []
        if not _present(selected_card):
            blockers.append("EXACT_CARD_REF_MISSING")
        elif selected_card not in candidates or not _present(card.get("resolver_evidence_ref")):
            blockers.append("EXACT_CARD_NOT_PROVEN_BY_RESOLVER")
    elif card_state == "COMPATIBLE":
        selected_card = card.get("selected_card_ref")
        candidates = card.get("candidate_refs") or []
        if not _present(selected_card) or not _present(card.get("compatibility_evidence_ref")):
            blockers.append("COMPATIBLE_CARD_EVIDENCE_MISSING")
        elif selected_card not in candidates or not _present(card.get("resolver_evidence_ref")):
            blockers.append("COMPATIBLE_CARD_NOT_PROVEN_BY_RESOLVER")

    fallback = receipt.get("fallback") or {}
    manual_required = bool(fallback.get("manual_required"))
    selected_fallback = fallback.get("selected")
    attempts = fallback.get("attempts") or []
    manual_allowed = False

    if card_state in {"EXACT", "COMPATIBLE"}:
        if manual_required or selected_fallback not in (None, "CARD"):
            blockers.append("FALLBACK_USED_WHEN_CARD_RESOLVED")
    elif card_state == "NONE":
        ordered = contract["fallback"]["ordered_alternatives"]
        actual_kinds = [a.get("kind") for a in attempts if isinstance(a, dict)]
        if len(actual_kinds) != len(set(actual_kinds)):
            blockers.append("FALLBACK_DUPLICATE_ALTERNATIVE")
        by_kind = {a.get("kind"): a for a in attempts if isinstance(a, dict)}
        selected_kind: str | None = None
        for kind in ordered:
            attempt = by_kind.get(kind)
            if attempt is None:
                blockers.append(f"FALLBACK_ALTERNATIVE_NOT_ATTEMPTED:{kind}")
                continue
            status = attempt.get("status")
            if status == "PASS" and selected_kind is None:
                if not _present(attempt.get("evidence_ref")):
                    blockers.append(f"FALLBACK_PASS_EVIDENCE_MISSING:{kind}")
                selected_kind = kind
                break
            if status != "FAIL":
                blockers.append(f"FALLBACK_STATUS_INVALID:{kind}")
            elif not _present(attempt.get("reason")) or not _present(attempt.get("evidence_ref")):
                blockers.append(f"FALLBACK_FAILURE_EVIDENCE_MISSING:{kind}")

        expected_prefix = ordered[: ordered.index(selected_kind) + 1] if selected_kind is not None else ordered
        if actual_kinds != expected_prefix:
            blockers.append("FALLBACK_ORDER_NOT_PRESERVED")

        if selected_kind is not None:
            if selected_fallback != selected_kind:
                blockers.append("FALLBACK_SELECTED_MISMATCH")
            if manual_required:
                blockers.append("MANUAL_REQUESTED_WITH_SAFE_ALTERNATIVE")
        else:
            all_failed = all(
                isinstance(by_kind.get(kind), dict)
                and by_kind[kind].get("status") == "FAIL"
                and _present(by_kind[kind].get("reason"))
                and _present(by_kind[kind].get("evidence_ref"))
                for kind in ordered
            )
            manual_allowed = all_failed
            if manual_required and not all_failed:
                blockers.append("MANUAL_WITHOUT_EXHAUSTED_SAFE_ALTERNATIVES")
            if all_failed and not manual_required:
                blockers.append("NO_SAFE_FALLBACK_AND_MANUAL_NOT_DECLARED")

    learning = receipt.get("learning") or {}
    persist_requested = learning.get("persist_requested") is True
    learning_eligible = learning.get("eligible") is True
    required_learning = contract["learning_persistence"]["required_when_persisting"]
    learning_missing = [key for key in required_learning if not _present(learning.get(key))]
    learning_persist_allowed = bool(persist_requested and learning_eligible and not learning_missing and learning.get("verified") is True)
    if persist_requested and not learning_persist_allowed:
        warnings.append("LEARNING_PERSISTENCE_DENIED_INSUFFICIENT_PROVENANCE")

    if blockers:
        result = "FAIL_CLOSED"
        execution_allowed = False
    elif card_state == "NONE" and manual_required and manual_allowed:
        result = "MANUAL_REQUIRED"
        execution_allowed = False
    else:
        result = "PASS_TO_EXECUTION"
        execution_allowed = True

    return {
        "result": result,
        "execution_allowed": execution_allowed,
        "manual_allowed": manual_allowed,
        "manual_avoided": bool(card_state == "NONE" and selected_fallback in contract["fallback"]["ordered_alternatives"] and not manual_required),
        "applicable_controls": applicable_controls,
        "learning_persist_allowed": learning_persist_allowed,
        "learning_missing_fields": learning_missing,
        "blockers": blockers,
        "warnings": warnings,
    }


def _base_receipt(contract: dict[str, Any]) -> dict[str, Any]:
    return {
        "pre_ekb_contract": {"contract_code": "CONTRACT-PRE-EKB-GATE-LF-v0.1", "status": "ACTIVE_ENFORCEMENT"},
        "sequence": list(contract["mandatory_sequence"]),
        "execution_started_before_gate": False,
        "applicability": {"status": "APPLICABLE", "surface": "GENERIC_DECISION", "critical_ambiguity": False},
        "ekb_readback": {"performed": True, "source_refs": ["supabase://public.lf_error_knowledge"], "snapshot_digest": "sha256:selftest-ekb"},
        "ekb_rules": [{"rule_code": "GOV-010", "applicability": "APPLICABLE", "severity": "HIGH", "control_ref": "PRE_EKB_GATE"}],
        "ekb_contradictions": [],
        "schema_policy": {"schema_invented": False, "data_model_mutated_to_fit_surface": False},
        "card_resolution": {"state": "EXACT", "selected_card_ref": "cards/example/CARD.md", "candidate_refs": ["cards/example/CARD.md"], "resolver_evidence_ref": "evidence://card-resolver"},
        "fallback": {"attempts": [], "selected": "CARD", "manual_required": False},
        "learning": {"persist_requested": False, "eligible": False, "verified": False}
    }


def self_test(contract: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], str, bool | None]] = []

    exact = _base_receipt(contract)
    cases.append(("01_card_exact", exact, "PASS_TO_EXECUTION", None))

    compatible = _base_receipt(contract)
    compatible["card_resolution"] = {"state": "COMPATIBLE", "selected_card_ref": "cards/generic/CARD.md", "candidate_refs": ["cards/generic/CARD.md"], "resolver_evidence_ref": "evidence://card-resolver", "compatibility_evidence_ref": "evidence://compatibility"}
    cases.append(("02_card_compatible", compatible, "PASS_TO_EXECUTION", None))

    generic = _base_receipt(contract)
    generic["card_resolution"] = {"state": "NONE"}
    generic["fallback"] = {"attempts": [
        {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "no matching contract", "evidence_ref": "evidence://contract-none"},
        {"kind": "GENERIC_CAPABILITY", "status": "PASS", "evidence_ref": "evidence://generic-capability"}
    ], "selected": "GENERIC_CAPABILITY", "manual_required": False}
    cases.append(("03_no_card_generic", generic, "PASS_TO_EXECUTION", True))

    composition = copy.deepcopy(generic)
    composition["fallback"] = {"attempts": [
        {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "no matching contract", "evidence_ref": "evidence://contract-none"},
        {"kind": "GENERIC_CAPABILITY", "status": "FAIL", "reason": "capability insufficient", "evidence_ref": "evidence://generic-fail"},
        {"kind": "SAFE_COMPOSITION", "status": "PASS", "evidence_ref": "evidence://composition"}
    ], "selected": "SAFE_COMPOSITION", "manual_required": False}
    cases.append(("04_no_card_safe_composition", composition, "PASS_TO_EXECUTION", True))

    manual = copy.deepcopy(composition)
    manual["fallback"] = {"attempts": [
        {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "no matching contract", "evidence_ref": "evidence://contract-none"},
        {"kind": "GENERIC_CAPABILITY", "status": "FAIL", "reason": "capability insufficient", "evidence_ref": "evidence://generic-fail"},
        {"kind": "SAFE_COMPOSITION", "status": "FAIL", "reason": "composition unsafe", "evidence_ref": "evidence://composition-fail"}
    ], "selected": None, "manual_required": True}
    cases.append(("05_manual_last_resort", manual, "MANUAL_REQUIRED", False))

    ekb_applicable = _base_receipt(contract)
    cases.append(("06_ekb_applicable", ekb_applicable, "PASS_TO_EXECUTION", None))

    ekb_na = _base_receipt(contract)
    ekb_na["ekb_rules"] = [{"rule_code": "UI-ONLY-001", "applicability": "NOT_APPLICABLE", "severity": "MEDIUM", "reason": "surface is governance-only"}]
    cases.append(("07_ekb_not_applicable", ekb_na, "PASS_TO_EXECUTION", None))

    contradiction = _base_receipt(contract)
    contradiction["ekb_contradictions"] = [{"rule_a": "A", "rule_b": "B", "status": "UNRESOLVED"}]
    cases.append(("08_rule_contradiction", contradiction, "FAIL_CLOSED", None))

    learning_bad = _base_receipt(contract)
    learning_bad["learning"] = {"persist_requested": True, "eligible": True, "verified": False, "cause": "observed cause"}
    cases.append(("09_learning_without_evidence", learning_bad, "PASS_TO_EXECUTION", None))

    learning_good = _base_receipt(contract)
    learning_good["learning"] = {
        "persist_requested": True, "eligible": True, "verified": True,
        "cause": "verified cause", "evidence_ref": "evidence://case-10", "evidence_digest": "sha256:case10",
        "applicability": "S26 governance requests", "prevention": "enforce deterministic pre-gate", "provenance": "SELFTEST"
    }
    cases.append(("10_learning_valid", learning_good, "PASS_TO_EXECUTION", None))

    ambiguity = _base_receipt(contract)
    ambiguity["applicability"]["critical_ambiguity"] = True
    cases.append(("11_critical_ambiguity", ambiguity, "FAIL_CLOSED", None))

    pre_missing = _base_receipt(contract)
    pre_missing["pre_ekb_contract"]["status"] = "MISSING"
    cases.append(("12_pre_ekb_missing", pre_missing, "FAIL_CLOSED", None))

    results = []
    for name, fixture, expected_result, expected_manual_avoided in cases:
        out = evaluate(contract, fixture)
        assert out["result"] == expected_result, (name, out)
        if expected_manual_avoided is not None:
            assert out["manual_avoided"] is expected_manual_avoided, (name, out)
        if name == "09_learning_without_evidence":
            assert out["learning_persist_allowed"] is False and "LEARNING_PERSISTENCE_DENIED_INSUFFICIENT_PROVENANCE" in out["warnings"]
        if name == "10_learning_valid":
            assert out["learning_persist_allowed"] is True
        results.append({"case": name, "result": out["result"], "manual_avoided": out["manual_avoided"], "learning_persist_allowed": out["learning_persist_allowed"]})

    return {"status": "PASS", "cases_passed": len(results), "cases": results}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, default=CONTRACT_DEFAULT)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    contract = load_json(args.contract)
    output: dict[str, Any] = {}
    if args.self_test:
        output["self_test"] = self_test(contract)
    if args.input:
        output["evaluation"] = evaluate(contract, load_json(args.input))
    if not output:
        parser.error("use --self-test and/or --input")
    print(json.dumps(output, indent=2, sort_keys=True))
    if args.input and output["evaluation"]["result"] == "FAIL_CLOSED":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
