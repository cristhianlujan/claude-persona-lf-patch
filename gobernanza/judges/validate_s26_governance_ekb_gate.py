#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from typing import Any

CONTRACT_DEFAULT = Path(__file__).resolve().parents[1] / "contratos" / "s26_governance_ekb_card_fallback_v1.json"
REPO_ROOT = Path(__file__).resolve().parents[2]
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
ALLOWED_EVIDENCE_PREFIXES = ("repo://", "github://", "supabase://", "github-actions://", "run:")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _present(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _failure(blockers: list[str], warnings: list[str] | None = None) -> dict[str, Any]:
    return {
        "result": "FAIL_CLOSED",
        "execution_allowed": False,
        "manual_allowed": False,
        "manual_avoided": False,
        "applicable_controls": [],
        "learning_persist_allowed": False,
        "learning_missing_fields": [],
        "blockers": blockers,
        "warnings": warnings or [],
    }


def _as_dict(value: Any, code: str, blockers: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        blockers.append(code)
        return {}
    return value


def _as_list(value: Any, code: str, blockers: list[str]) -> list[Any]:
    if not isinstance(value, list):
        blockers.append(code)
        return []
    return value


def _valid_evidence_ref(value: Any) -> bool:
    return _present(value) and str(value).startswith(ALLOWED_EVIDENCE_PREFIXES)


def _validate_repo_ref(value: str, blockers: list[str], code: str) -> Path | None:
    if not value.startswith("repo://"):
        return None
    raw = value[len("repo://"):].split("#", 1)[0].strip()
    if not raw:
        blockers.append(code)
        return None
    candidate = (REPO_ROOT / raw).resolve()
    try:
        candidate.relative_to(REPO_ROOT)
    except ValueError:
        blockers.append(code)
        return None
    if not candidate.is_file():
        blockers.append(code)
        return None
    return candidate


def _canonical_sha256(payload: Any) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def _snapshot_payload(readback: dict[str, Any], contract: dict[str, Any], blockers: list[str]) -> dict[str, Any]:
    digest = readback.get("snapshot_digest")
    if not _present(digest) or SHA256_RE.fullmatch(str(digest)) is None:
        blockers.append("EKB_SNAPSHOT_DIGEST_INVALID")
    snapshot_ref = readback.get("snapshot_ref")
    if not _valid_evidence_ref(snapshot_ref) or not str(snapshot_ref).startswith("repo://"):
        blockers.append("EKB_SNAPSHOT_REF_INVALID")
        return {}
    path = _validate_repo_ref(str(snapshot_ref), blockers, "EKB_SNAPSHOT_REF_UNRESOLVED")
    if path is None:
        return {}
    try:
        snapshot = load_json(path)
    except (OSError, json.JSONDecodeError):
        blockers.append("EKB_SNAPSHOT_UNREADABLE")
        return {}
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("payload"), dict):
        blockers.append("EKB_SNAPSHOT_SHAPE_INVALID")
        return {}
    payload = snapshot["payload"]
    computed = _canonical_sha256(payload)
    if digest != computed:
        blockers.append("EKB_SNAPSHOT_DIGEST_MISMATCH")

    expected_codes = contract["ekb"]["minimum_rule_codes"]
    if payload.get("minimum_rule_codes") != expected_codes:
        blockers.append("EKB_SNAPSHOT_MINIMUM_RULE_SET_MISMATCH")

    snap_pre = payload.get("pre_ekb_contract")
    expected_pre = contract["existing_pre_ekb_contract"]
    if not isinstance(snap_pre, dict) or snap_pre.get("contract_code") != expected_pre["contract_code"] or snap_pre.get("status") != expected_pre["required_status"]:
        blockers.append("EKB_SNAPSHOT_PRE_EKB_AUTHORITY_MISMATCH")
    return payload


def _validate_evidence_ref(value: Any, blockers: list[str], missing_code: str, unresolved_code: str) -> None:
    if not _valid_evidence_ref(value):
        blockers.append(missing_code)
        return
    if str(value).startswith("repo://"):
        _validate_repo_ref(str(value), blockers, unresolved_code)


def evaluate(contract: dict[str, Any], receipt: Any) -> dict[str, Any]:
    if not isinstance(contract, dict):
        return _failure(["CONTRACT_SHAPE_INVALID"])
    if not isinstance(receipt, dict):
        return _failure(["RECEIPT_SHAPE_INVALID"])

    blockers: list[str] = []
    warnings: list[str] = []

    pre = _as_dict(receipt.get("pre_ekb_contract"), "PRE_EKB_CONTRACT_SHAPE_INVALID", blockers)
    expected_pre = contract["existing_pre_ekb_contract"]
    if pre.get("contract_code") != expected_pre["contract_code"] or pre.get("status") != expected_pre["required_status"]:
        blockers.append("PRE_EKB_CONTRACT_NOT_ACTIVE")
    _validate_evidence_ref(pre.get("evidence_ref"), blockers, "PRE_EKB_EVIDENCE_REF_MISSING", "PRE_EKB_EVIDENCE_REF_UNRESOLVED")

    sequence = _as_list(receipt.get("sequence"), "MANDATORY_SEQUENCE_SHAPE_INVALID", blockers)
    if sequence != contract["mandatory_sequence"]:
        blockers.append("MANDATORY_SEQUENCE_NOT_PROVEN")
    if receipt.get("execution_started_before_gate") is not False:
        blockers.append("EXECUTION_STARTED_BEFORE_PREEXECUTION_GATE")

    applicability = _as_dict(receipt.get("applicability"), "APPLICABILITY_SHAPE_INVALID", blockers)
    applicability_status = applicability.get("status")
    if applicability.get("critical_ambiguity") is True:
        blockers.append("CRITICAL_APPLICABILITY_AMBIGUITY")
    if applicability_status not in contract["applicability"]["allowed"]:
        blockers.append("APPLICABILITY_UNRESOLVED")
    if not _present(applicability.get("surface")):
        blockers.append("APPLICABILITY_SURFACE_MISSING")
    _validate_evidence_ref(applicability.get("evidence_ref"), blockers, "APPLICABILITY_EVIDENCE_REF_MISSING", "APPLICABILITY_EVIDENCE_REF_UNRESOLVED")
    if applicability_status == "NOT_APPLICABLE" and not _present(applicability.get("reason")):
        blockers.append("NOT_APPLICABLE_REASON_MISSING")

    readback = _as_dict(receipt.get("ekb_readback"), "EKB_READBACK_SHAPE_INVALID", blockers)
    source_refs = _as_list(readback.get("source_refs"), "EKB_SOURCE_REFS_SHAPE_INVALID", blockers)
    if readback.get("performed") is not True or not source_refs or any(not _valid_evidence_ref(ref) for ref in source_refs):
        blockers.append("EKB_READBACK_INCOMPLETE")
    snapshot_payload = _snapshot_payload(readback, contract, blockers)
    snapshot_rules = snapshot_payload.get("rules") if isinstance(snapshot_payload, dict) else []
    if not isinstance(snapshot_rules, list):
        blockers.append("EKB_SNAPSHOT_RULES_SHAPE_INVALID")
        snapshot_rules = []
    snapshot_map: dict[str, dict[str, Any]] = {}
    for idx, item in enumerate(snapshot_rules):
        if not isinstance(item, dict) or not _present(item.get("codigo")):
            blockers.append(f"EKB_SNAPSHOT_RULE_SHAPE_INVALID:{idx}")
            continue
        code = str(item["codigo"])
        if code in snapshot_map:
            blockers.append(f"EKB_SNAPSHOT_RULE_DUPLICATE:{code}")
        snapshot_map[code] = item

    rules = _as_list(receipt.get("ekb_rules"), "EKB_RULES_SHAPE_INVALID", blockers)
    applicable_controls: list[str] = []
    considered_codes: list[str] = []
    for idx, rule_raw in enumerate(rules):
        if not isinstance(rule_raw, dict):
            blockers.append(f"EKB_RULE_SHAPE_INVALID:{idx}")
            continue
        rule = rule_raw
        code = rule.get("rule_code")
        if not _present(code):
            blockers.append(f"EKB_RULE_CODE_MISSING:{idx}")
            continue
        code = str(code)
        if code in considered_codes:
            blockers.append(f"EKB_RULE_DUPLICATE:{code}")
        considered_codes.append(code)
        snap = snapshot_map.get(code)
        if snap is None or snap.get("estado") != "activo":
            blockers.append(f"EKB_RULE_NOT_IN_ACTIVE_SNAPSHOT:{code}")
            snap = {}
        state = rule.get("applicability")
        if state not in contract["applicability"]["allowed"]:
            blockers.append(f"EKB_RULE_APPLICABILITY_UNRESOLVED:{code}")
            continue
        _validate_evidence_ref(rule.get("evidence_ref"), blockers, f"EKB_RULE_EVIDENCE_MISSING:{code}", f"EKB_RULE_EVIDENCE_UNRESOLVED:{code}")
        if state == "NOT_APPLICABLE":
            if not _present(rule.get("reason")):
                blockers.append(f"EKB_RULE_NA_REASON_MISSING:{code}")
            continue
        control_ref = rule.get("control_ref")
        severity = str(snap.get("severidad", "")).upper()
        if not _present(control_ref):
            blockers.append(f"APPLICABLE_EKB_RULE_WITHOUT_CONTROL:{code}")
            if severity in {"HIGH", "CRITICAL"}:
                blockers.append(f"UNHANDLED_HIGH_CRITICAL_EKB_RULE:{code}")
        else:
            applicable_controls.append(str(control_ref))

    missing_minimum = [code for code in contract["ekb"]["minimum_rule_codes"] if code not in considered_codes]
    for code in missing_minimum:
        blockers.append(f"MINIMUM_EKB_RULE_NOT_CONSIDERED:{code}")

    contradictions = _as_list(receipt.get("ekb_contradictions"), "EKB_CONTRADICTIONS_SHAPE_INVALID", blockers)
    for idx, contradiction in enumerate(contradictions):
        if not isinstance(contradiction, dict):
            blockers.append(f"EKB_CONTRADICTION_SHAPE_INVALID:{idx}")
            continue
        if contradiction.get("status") != "RESOLVED" or not _present(contradiction.get("resolution_ref")):
            blockers.append(f"EKB_CONTRADICTION_UNRESOLVED:{idx}")

    schema_policy = _as_dict(receipt.get("schema_policy"), "SCHEMA_POLICY_SHAPE_INVALID", blockers)
    if schema_policy.get("schema_invented") is not False:
        blockers.append("SCHEMA_INVENTION_FORBIDDEN")
    if schema_policy.get("data_model_mutated_to_fit_surface") is not False:
        blockers.append("DATA_MODEL_MUTATION_FORBIDDEN")

    card = _as_dict(receipt.get("card_resolution"), "CARD_RESOLUTION_SHAPE_INVALID", blockers)
    card_state = card.get("state")
    if card_state not in contract["card_resolution"]["states"]:
        blockers.append("CARD_STATE_INVALID")
    elif card_state == "AMBIGUOUS":
        blockers.append("CARD_AMBIGUOUS_FAIL_CLOSED")
    elif card_state in {"EXACT", "COMPATIBLE"}:
        candidates = card.get("candidate_refs")
        if not isinstance(candidates, list) or not candidates or any(not _present(x) for x in candidates):
            blockers.append("CARD_CANDIDATE_REFS_INVALID")
            candidates = []
        elif len(candidates) != len(set(candidates)):
            blockers.append("CARD_CANDIDATE_REFS_DUPLICATE")
        selected = card.get("selected_card_ref")
        if not _present(selected):
            blockers.append(f"{card_state}_CARD_REF_MISSING")
        elif selected not in candidates:
            blockers.append(f"{card_state}_CARD_NOT_PROVEN_BY_RESOLVER")
        _validate_evidence_ref(card.get("resolver_evidence_ref"), blockers, "CARD_RESOLVER_EVIDENCE_MISSING", "CARD_RESOLVER_EVIDENCE_UNRESOLVED")
        if card_state == "COMPATIBLE":
            _validate_evidence_ref(card.get("compatibility_evidence_ref"), blockers, "COMPATIBLE_CARD_EVIDENCE_MISSING", "COMPATIBLE_CARD_EVIDENCE_UNRESOLVED")
    elif card_state == "NONE":
        _validate_evidence_ref(card.get("resolver_evidence_ref"), blockers, "NO_CARD_RESOLVER_EVIDENCE_MISSING", "NO_CARD_RESOLVER_EVIDENCE_UNRESOLVED")

    fallback = _as_dict(receipt.get("fallback"), "FALLBACK_SHAPE_INVALID", blockers)
    if not isinstance(fallback.get("manual_required"), bool):
        blockers.append("MANUAL_REQUIRED_TYPE_INVALID")
    manual_required = fallback.get("manual_required") is True
    selected_fallback = fallback.get("selected")
    attempts = _as_list(fallback.get("attempts"), "FALLBACK_ATTEMPTS_SHAPE_INVALID", blockers)
    manual_allowed = False

    if card_state in {"EXACT", "COMPATIBLE"}:
        if manual_required or selected_fallback not in (None, "CARD"):
            blockers.append("FALLBACK_USED_WHEN_CARD_RESOLVED")
    elif card_state == "NONE":
        ordered = contract["fallback"]["ordered_alternatives"]
        if any(not isinstance(a, dict) for a in attempts):
            blockers.append("FALLBACK_ATTEMPT_SHAPE_INVALID")
        typed_attempts = [a for a in attempts if isinstance(a, dict)]
        actual_kinds = [a.get("kind") for a in typed_attempts]
        if any(kind not in ordered for kind in actual_kinds):
            blockers.append("FALLBACK_UNKNOWN_ALTERNATIVE")
        if len(actual_kinds) != len(set(actual_kinds)):
            blockers.append("FALLBACK_DUPLICATE_ALTERNATIVE")
        by_kind = {a.get("kind"): a for a in typed_attempts if a.get("kind") in ordered}
        selected_kind: str | None = None
        for kind in ordered:
            attempt = by_kind.get(kind)
            if attempt is None:
                blockers.append(f"FALLBACK_ALTERNATIVE_NOT_ATTEMPTED:{kind}")
                continue
            status = attempt.get("status")
            if status == "PASS" and selected_kind is None:
                _validate_evidence_ref(attempt.get("evidence_ref"), blockers, f"FALLBACK_PASS_EVIDENCE_MISSING:{kind}", f"FALLBACK_PASS_EVIDENCE_UNRESOLVED:{kind}")
                selected_kind = kind
                break
            if status != "FAIL":
                blockers.append(f"FALLBACK_STATUS_INVALID:{kind}")
            else:
                if not _present(attempt.get("reason")):
                    blockers.append(f"FALLBACK_FAILURE_REASON_MISSING:{kind}")
                _validate_evidence_ref(attempt.get("evidence_ref"), blockers, f"FALLBACK_FAILURE_EVIDENCE_MISSING:{kind}", f"FALLBACK_FAILURE_EVIDENCE_UNRESOLVED:{kind}")

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
                and _valid_evidence_ref(by_kind[kind].get("evidence_ref"))
                for kind in ordered
            )
            manual_allowed = all_failed
            if manual_required and not all_failed:
                blockers.append("MANUAL_WITHOUT_EXHAUSTED_SAFE_ALTERNATIVES")
            if all_failed and not manual_required:
                blockers.append("NO_SAFE_FALLBACK_AND_MANUAL_NOT_DECLARED")

    learning = _as_dict(receipt.get("learning"), "LEARNING_SHAPE_INVALID", blockers)
    if not isinstance(learning.get("persist_requested"), bool):
        blockers.append("LEARNING_PERSIST_REQUESTED_TYPE_INVALID")
    if not isinstance(learning.get("eligible"), bool):
        blockers.append("LEARNING_ELIGIBLE_TYPE_INVALID")
    if not isinstance(learning.get("verified"), bool):
        blockers.append("LEARNING_VERIFIED_TYPE_INVALID")
    persist_requested = learning.get("persist_requested") is True
    learning_eligible = learning.get("eligible") is True
    required_learning = contract["learning_persistence"]["required_when_persisting"]
    learning_missing = [key for key in required_learning if not _present(learning.get(key))] if persist_requested else []
    digest_ok = (not persist_requested) or (SHA256_RE.fullmatch(str(learning.get("evidence_digest", ""))) is not None)
    if persist_requested and not digest_ok:
        learning_missing.append("evidence_digest_valid_sha256")
    if persist_requested:
        learning_ref = learning.get("evidence_ref")
        learning_ref_errors: list[str] = []
        if not _valid_evidence_ref(learning_ref):
            learning_missing.append("evidence_ref_valid")
        elif str(learning_ref).startswith("repo://"):
            _validate_repo_ref(str(learning_ref), learning_ref_errors, "LEARNING_EVIDENCE_REF_UNRESOLVED")
            if learning_ref_errors:
                learning_missing.append("evidence_ref_resolvable")
    learning_persist_allowed = bool(persist_requested and learning_eligible and not learning_missing and learning.get("verified") is True)
    if persist_requested and not learning_persist_allowed:
        warnings.append("LEARNING_PERSISTENCE_DENIED_INSUFFICIENT_PROVENANCE")

    if blockers:
        result = "FAIL_CLOSED"
        execution_allowed = False
    elif applicability_status == "NOT_APPLICABLE":
        result = "NOT_APPLICABLE"
        execution_allowed = False
    elif card_state == "NONE" and manual_required and manual_allowed:
        result = "MANUAL_REQUIRED"
        execution_allowed = False
    else:
        result = "PASS_TO_EXECUTION"
        execution_allowed = True

    manual_avoided = bool(result == "PASS_TO_EXECUTION" and card_state == "NONE" and selected_fallback in contract["fallback"]["ordered_alternatives"] and not manual_required)

    return {
        "result": result,
        "execution_allowed": execution_allowed,
        "manual_allowed": manual_allowed,
        "manual_avoided": manual_avoided,
        "applicable_controls": applicable_controls,
        "learning_persist_allowed": learning_persist_allowed,
        "learning_missing_fields": sorted(set(learning_missing)),
        "blockers": blockers,
        "warnings": warnings,
    }


def _base_receipt(contract: dict[str, Any]) -> dict[str, Any]:
    evidence = "repo://sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_preexecution_evidence_v2.json"
    codes = contract["ekb"]["minimum_rule_codes"]
    rules = []
    for code in codes:
        rules.append({"rule_code": code, "applicability": "NOT_APPLICABLE", "reason": "self-test default non-applicability", "evidence_ref": evidence})
    for item in rules:
        if item["rule_code"] == "GOV-010":
            item["applicability"] = "APPLICABLE"
            item.pop("reason", None)
            item["control_ref"] = "CONTRACT-PRE-EKB-GATE-LF-v0.1"
    return {
        "pre_ekb_contract": {"contract_code": "CONTRACT-PRE-EKB-GATE-LF-v0.1", "status": "ACTIVE_ENFORCEMENT", "evidence_ref": evidence},
        "sequence": list(contract["mandatory_sequence"]),
        "execution_started_before_gate": False,
        "applicability": {"status": "APPLICABLE", "surface": "GENERIC_DECISION", "critical_ambiguity": False, "evidence_ref": evidence},
        "ekb_readback": {"performed": True, "source_refs": ["supabase://public.lf_error_knowledge"], "snapshot_ref": evidence, "snapshot_digest": contract["ekb"]["self_test_snapshot_digest"]},
        "ekb_rules": rules,
        "ekb_contradictions": [],
        "schema_policy": {"schema_invented": False, "data_model_mutated_to_fit_surface": False},
        "card_resolution": {"state": "EXACT", "selected_card_ref": "cards/marketplace_lf/decision_product_experience/CARD.md", "candidate_refs": ["cards/marketplace_lf/decision_product_experience/CARD.md"], "resolver_evidence_ref": evidence},
        "fallback": {"attempts": [], "selected": "CARD", "manual_required": False},
        "learning": {"persist_requested": False, "eligible": False, "verified": False},
    }


def self_test(contract: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, Any, str, bool | None]] = []
    exact = _base_receipt(contract)
    cases.append(("01_card_exact", exact, "PASS_TO_EXECUTION", None))

    compatible = _base_receipt(contract)
    compatible["card_resolution"] = {"state": "COMPATIBLE", "selected_card_ref": "cards/marketplace_lf/decision_product_experience/CARD.md", "candidate_refs": ["cards/marketplace_lf/decision_product_experience/CARD.md"], "resolver_evidence_ref": exact["applicability"]["evidence_ref"], "compatibility_evidence_ref": exact["applicability"]["evidence_ref"]}
    cases.append(("02_card_compatible", compatible, "PASS_TO_EXECUTION", None))

    generic = _base_receipt(contract)
    generic["card_resolution"] = {"state": "NONE", "resolver_evidence_ref": exact["applicability"]["evidence_ref"]}
    generic["fallback"] = {"attempts": [
        {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "no matching contract", "evidence_ref": exact["applicability"]["evidence_ref"]},
        {"kind": "GENERIC_CAPABILITY", "status": "PASS", "evidence_ref": exact["applicability"]["evidence_ref"]},
    ], "selected": "GENERIC_CAPABILITY", "manual_required": False}
    cases.append(("03_no_card_generic", generic, "PASS_TO_EXECUTION", True))

    composition = copy.deepcopy(generic)
    composition["fallback"] = {"attempts": [
        {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "no matching contract", "evidence_ref": exact["applicability"]["evidence_ref"]},
        {"kind": "GENERIC_CAPABILITY", "status": "FAIL", "reason": "capability insufficient", "evidence_ref": exact["applicability"]["evidence_ref"]},
        {"kind": "SAFE_COMPOSITION", "status": "PASS", "evidence_ref": exact["applicability"]["evidence_ref"]},
    ], "selected": "SAFE_COMPOSITION", "manual_required": False}
    cases.append(("04_no_card_safe_composition", composition, "PASS_TO_EXECUTION", True))

    manual = copy.deepcopy(composition)
    manual["fallback"] = {"attempts": [
        {"kind": "CONTRACT_SCHEMA", "status": "FAIL", "reason": "no matching contract", "evidence_ref": exact["applicability"]["evidence_ref"]},
        {"kind": "GENERIC_CAPABILITY", "status": "FAIL", "reason": "capability insufficient", "evidence_ref": exact["applicability"]["evidence_ref"]},
        {"kind": "SAFE_COMPOSITION", "status": "FAIL", "reason": "composition unsafe", "evidence_ref": exact["applicability"]["evidence_ref"]},
    ], "selected": None, "manual_required": True}
    cases.append(("05_manual_last_resort", manual, "MANUAL_REQUIRED", False))

    cases.append(("06_ekb_applicable", _base_receipt(contract), "PASS_TO_EXECUTION", None))
    ekb_na = _base_receipt(contract)
    for rule in ekb_na["ekb_rules"]:
        rule["applicability"] = "NOT_APPLICABLE"
        rule.pop("control_ref", None)
        rule["reason"] = "not applicable for this self-test fixture"
    cases.append(("07_ekb_not_applicable", ekb_na, "PASS_TO_EXECUTION", None))

    contradiction = _base_receipt(contract)
    contradiction["ekb_contradictions"] = [{"rule_a": "A", "rule_b": "B", "status": "UNRESOLVED"}]
    cases.append(("08_rule_contradiction", contradiction, "FAIL_CLOSED", None))

    learning_bad = _base_receipt(contract)
    learning_bad["learning"] = {"persist_requested": True, "eligible": True, "verified": False, "cause": "observed cause"}
    cases.append(("09_learning_without_evidence", learning_bad, "PASS_TO_EXECUTION", None))

    learning_good = _base_receipt(contract)
    learning_good["learning"] = {"persist_requested": True, "eligible": True, "verified": True, "cause": "verified cause", "evidence_ref": exact["applicability"]["evidence_ref"], "evidence_digest": contract["ekb"]["self_test_snapshot_digest"], "applicability": "S26 governance requests", "prevention": "enforce deterministic pre-gate", "provenance": "SELFTEST"}
    cases.append(("10_learning_valid", learning_good, "PASS_TO_EXECUTION", None))

    ambiguity = _base_receipt(contract)
    ambiguity["applicability"]["critical_ambiguity"] = True
    cases.append(("11_critical_ambiguity", ambiguity, "FAIL_CLOSED", None))

    pre_missing = _base_receipt(contract)
    pre_missing["pre_ekb_contract"]["status"] = "MISSING"
    cases.append(("12_pre_ekb_missing", pre_missing, "FAIL_CLOSED", None))

    skipped = copy.deepcopy(generic)
    skipped["fallback"] = {"attempts": [{"kind": "GENERIC_CAPABILITY", "status": "PASS", "evidence_ref": exact["applicability"]["evidence_ref"]}], "selected": "GENERIC_CAPABILITY", "manual_required": False}
    cases.append(("13_skip_fallback_order", skipped, "FAIL_CLOSED", False))

    bad_digest = _base_receipt(contract)
    bad_digest["ekb_readback"]["snapshot_digest"] = "sha256:not-a-real-digest"
    cases.append(("14_invalid_snapshot_digest", bad_digest, "FAIL_CLOSED", None))

    missing_rule = _base_receipt(contract)
    missing_rule["ekb_rules"] = missing_rule["ekb_rules"][:-1]
    cases.append(("15_missing_minimum_rule", missing_rule, "FAIL_CLOSED", None))

    malformed_rule = _base_receipt(contract)
    malformed_rule["ekb_rules"][0] = "not-an-object"
    cases.append(("16_malformed_rule_fail_closed", malformed_rule, "FAIL_CLOSED", None))

    malformed_fallback = copy.deepcopy(generic)
    malformed_fallback["fallback"]["attempts"].append("junk")
    cases.append(("17_malformed_fallback_fail_closed", malformed_fallback, "FAIL_CLOSED", False))

    card_candidates_string = _base_receipt(contract)
    card_candidates_string["card_resolution"]["candidate_refs"] = "cards/marketplace_lf/decision_product_experience/CARD.md"
    cases.append(("18_card_candidate_shape", card_candidates_string, "FAIL_CLOSED", None))

    top_na = _base_receipt(contract)
    top_na["applicability"] = {"status": "NOT_APPLICABLE", "surface": "OUT_OF_SCOPE", "critical_ambiguity": False, "reason": "surface is not owned by S26-E", "evidence_ref": exact["applicability"]["evidence_ref"]}
    cases.append(("19_top_level_not_applicable_no_execute", top_na, "NOT_APPLICABLE", None))
    cases.append(("20_receipt_shape_fail_closed", [], "FAIL_CLOSED", False))

    results = []
    for name, fixture, expected_result, expected_manual_avoided in cases:
        out = evaluate(contract, fixture)
        assert out["result"] == expected_result, (name, out)
        if expected_manual_avoided is not None:
            assert out["manual_avoided"] is expected_manual_avoided, (name, out)
        if name == "09_learning_without_evidence":
            assert out["learning_persist_allowed"] is False
        if name == "10_learning_valid":
            assert out["learning_persist_allowed"] is True
        if name == "19_top_level_not_applicable_no_execute":
            assert out["execution_allowed"] is False
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
