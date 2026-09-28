#!/usr/bin/env python3
from __future__ import annotations

import copy
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_predicate_semantics"))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_check_core"))

import legacy_contract_normalization_v1 as norm
import contract_predicate_semantics_v1 as semantics
import contract_check_core_v1 as core


def contract(code: str, op: str, rbw: Any, allowed: Any, blocked: Any, raw: Any) -> dict[str, Any]:
    return {
        "operation_code": op,
        "contract_code": code,
        "required_before_write": rbw,
        "allowed": allowed,
        "blocked": blocked,
        "required_after_write": raw,
    }


def mapping(section: str, pointer: str, expected: Any, term_id: str, predicate: dict[str, Any]) -> dict[str, Any]:
    return {
        "section": section,
        "source_pointer": pointer,
        "expected_source": expected,
        "typed_term": {"id": term_id, "predicate": predicate},
    }


def translation(c: dict[str, Any], mappings: list[dict[str, Any]], mode: str = "FULL") -> dict[str, Any]:
    return {
        "schema_version": norm.TRANSLATION_SCHEMA_VERSION,
        "operation_code": c["operation_code"],
        "contract_code": c["contract_code"],
        "source_contract_sha256": norm._sha(c),
        "coverage_mode": mode,
        "mappings": mappings,
    }


def packet(c: dict[str, Any], t: dict[str, Any]) -> dict[str, Any]:
    return {"schema_version": norm.INPUT_SCHEMA_VERSION, "legacy_contract": c, "translation": t}


def standard_fixture() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    c = contract(
        "CONTRACT-SAMPLE-STANDARD-v1",
        "SAMPLE_STANDARD",
        ["router_read"],
        {"runtime_enable": False},
        ["production_enable"],
        ["exact_readback"],
    )
    m = [
        mapping("required_before_write", "/required_before_write/0", "router_read", "router_read", {"op": "TRUE", "fact": "router.read"}),
        mapping("allowed", "/allowed/runtime_enable", False, "runtime_disabled", {"op": "FALSE", "fact": "runtime.enable_requested"}),
        mapping("blocked", "/blocked/0", "production_enable", "production_enable", {"op": "TRUE", "fact": "production.enable_requested"}),
        mapping("required_after_write", "/required_after_write/0", "exact_readback", "exact_readback", {"op": "TRUE", "fact": "readback.exact"}),
    ]
    return c, m


def expect_error(fn, token: str) -> None:
    try:
        fn()
    except norm.LegacyContractNormalizationError as exc:
        assert token in str(exc), (token, str(exc))
        return
    raise AssertionError(f"expected error containing {token}")


def case_standard_full_ready() -> None:
    c, m = standard_fixture()
    result = norm.normalize(packet(c, translation(c, m)))
    assert result["status"] == "READY"
    assert result["ready_for_contract_check"] is True
    assert result["coverage"] == {"mode": "FULL", "source_atoms": 4, "covered_atoms": 4, "missing_atoms": []}
    assert result["normalized_contract"] == result["candidate_contract"]


def case_blocked_object_shape_ready() -> None:
    c = contract("CONTRACT-SAMPLE-BLOCKED-OBJECT-v1", "SAMPLE_BLOCKED_OBJECT", ["ekb_preflight"], {"single_rule": True}, {"production_promotion": True}, ["readback"])
    m = [
        mapping("required_before_write", "/required_before_write/0", "ekb_preflight", "ekb_preflight", {"op": "TRUE", "fact": "ekb.preflight"}),
        mapping("allowed", "/allowed/single_rule", True, "single_rule", {"op": "TRUE", "fact": "rule.single"}),
        mapping("blocked", "/blocked/production_promotion", True, "production_promotion", {"op": "TRUE", "fact": "production.promotion_requested"}),
        mapping("required_after_write", "/required_after_write/0", "readback", "readback", {"op": "TRUE", "fact": "readback.done"}),
    ]
    result = norm.normalize(packet(c, translation(c, m)))
    assert result["status"] == "READY"
    assert len(result["normalized_contract"]["blocked"]) == 1


def case_all_object_shape_ready() -> None:
    c = contract("CONTRACT-SAMPLE-ALL-OBJECT-v1", "SAMPLE_ALL_OBJECT", {"must_read": True}, {"mode": "READ_ONLY"}, {"direct_write": "DENY"}, {"receipt_required": True})
    m = [
        mapping("required_before_write", "/required_before_write/must_read", True, "must_read", {"op": "TRUE", "fact": "source.read"}),
        mapping("allowed", "/allowed/mode", "READ_ONLY", "read_only", {"op": "EQ", "fact": "mode", "value": "READ_ONLY"}),
        mapping("blocked", "/blocked/direct_write", "DENY", "direct_write", {"op": "TRUE", "fact": "direct_write.requested"}),
        mapping("required_after_write", "/required_after_write/receipt_required", True, "receipt", {"op": "TRUE", "fact": "receipt.present"}),
    ]
    result = norm.normalize(packet(c, translation(c, m)))
    assert result["ready_for_contract_check"] is True
    assert result["coverage"]["source_atoms"] == 4


def case_object_array_object_shape_ready() -> None:
    c = contract("CONTRACT-SAMPLE-MIXED-v1", "SAMPLE_MIXED", {"exact_profile_required": True}, {"automatic_promotion": False}, ["STATE_DRIFT"], {"health_readback_required": True})
    m = [
        mapping("required_before_write", "/required_before_write/exact_profile_required", True, "exact_profile", {"op": "TRUE", "fact": "profile.exact"}),
        mapping("allowed", "/allowed/automatic_promotion", False, "no_auto_promotion", {"op": "FALSE", "fact": "promotion.automatic"}),
        mapping("blocked", "/blocked/0", "STATE_DRIFT", "state_drift", {"op": "TRUE", "fact": "state.drift"}),
        mapping("required_after_write", "/required_after_write/health_readback_required", True, "health_readback", {"op": "TRUE", "fact": "health.readback"}),
    ]
    result = norm.normalize(packet(c, translation(c, m)))
    assert result["status"] == "READY"
    assert result["coverage"]["covered_atoms"] == 4


def case_nested_object_atoms_are_explicit() -> None:
    c = contract("CONTRACT-SAMPLE-NESTED-v1", "SAMPLE_NESTED", {"gate": {"required": True}}, {"terminal": {"runtime": "NO_HABILITADO"}}, {"unsafe": {"deny": True}}, {"receipt": {"required": True}})
    m = [
        mapping("required_before_write", "/required_before_write/gate/required", True, "gate", {"op": "TRUE", "fact": "gate.pass"}),
        mapping("allowed", "/allowed/terminal/runtime", "NO_HABILITADO", "runtime_state", {"op": "EQ", "fact": "runtime.state", "value": "NO_HABILITADO"}),
        mapping("blocked", "/blocked/unsafe/deny", True, "unsafe", {"op": "TRUE", "fact": "unsafe.requested"}),
        mapping("required_after_write", "/required_after_write/receipt/required", True, "receipt", {"op": "TRUE", "fact": "receipt.present"}),
    ]
    result = norm.normalize(packet(c, translation(c, m)))
    assert result["coverage"]["source_atoms"] == 4
    assert result["ready_for_contract_check"] is True


def case_partial_shadow_never_ready() -> None:
    c, m = standard_fixture()
    result = norm.normalize(packet(c, translation(c, m[:2], "PARTIAL_SHADOW")))
    assert result["status"] == "PARTIAL_SHADOW"
    assert result["ready_for_contract_check"] is False
    assert result["normalized_contract"] is None
    assert len(result["coverage"]["missing_atoms"]) == 2


def case_full_incomplete_blocks() -> None:
    c, m = standard_fixture()
    expect_error(lambda: norm.normalize(packet(c, translation(c, m[:3], "FULL"))), "full_coverage_incomplete")


def case_source_sha_drift_blocks() -> None:
    c, m = standard_fixture()
    t = translation(c, m)
    drifted = copy.deepcopy(c)
    drifted["allowed"]["runtime_enable"] = True
    expect_error(lambda: norm.normalize(packet(drifted, t)), "source_contract_sha256_mismatch")


def case_expected_source_mismatch_blocks() -> None:
    c, m = standard_fixture()
    broken = copy.deepcopy(m)
    broken[0]["expected_source"] = "different"
    expect_error(lambda: norm.normalize(packet(c, translation(c, broken))), "mapping_source_value_mismatch")


def case_json_equality_is_type_strict() -> None:
    c, m = standard_fixture()
    broken = copy.deepcopy(m)
    broken[1]["expected_source"] = 0
    expect_error(lambda: norm.normalize(packet(c, translation(c, broken))), "mapping_source_value_mismatch")


def case_duplicate_source_mapping_blocks() -> None:
    c, m = standard_fixture()
    duplicated = m + [copy.deepcopy(m[0])]
    expect_error(lambda: norm.normalize(packet(c, translation(c, duplicated))), "duplicate_source_mapping")


def case_duplicate_typed_id_blocks() -> None:
    c = contract("CONTRACT-SAMPLE-DUP-ID-v1", "SAMPLE_DUP_ID", ["read_a", "read_b"], {}, [], [])
    m = [
        mapping("required_before_write", "/required_before_write/0", "read_a", "same", {"op": "TRUE", "fact": "a.read"}),
        mapping("required_before_write", "/required_before_write/1", "read_b", "same", {"op": "TRUE", "fact": "b.read"}),
    ]
    expect_error(lambda: norm.normalize(packet(c, translation(c, m))), "duplicate_typed_term_id")


def case_non_atom_pointer_blocks() -> None:
    c = contract("CONTRACT-SAMPLE-NON-ATOM-v1", "SAMPLE_NON_ATOM", {"gate": {"required": True}}, {}, [], [])
    m = [mapping("required_before_write", "/required_before_write/gate", {"required": True}, "gate", {"op": "TRUE", "fact": "gate.pass"})]
    expect_error(lambda: norm.normalize(packet(c, translation(c, m, "PARTIAL_SHADOW"))), "mapping_source_pointer_not_atom")


def case_identity_mismatch_blocks() -> None:
    c, m = standard_fixture()
    t = translation(c, m)
    t["operation_code"] = "OTHER_OPERATION"
    expect_error(lambda: norm.normalize(packet(c, t)), "translation_operation_mismatch")


def case_end_to_end_semantics_and_core_pass() -> None:
    c, m = standard_fixture()
    normalized = norm.normalize(packet(c, translation(c, m)))["normalized_contract"]
    facts = {
        "router.read": {"present": True, "value": True, "evidence_refs": ["evidence://router/read"]},
        "runtime.enable_requested": {"present": True, "value": False, "evidence_refs": ["evidence://runtime/request"]},
        "production.enable_requested": {"present": True, "value": False, "evidence_refs": ["evidence://production/request"]},
        "readback.exact": {"present": True, "value": True, "evidence_refs": ["evidence://readback/exact"]},
    }
    semantic_result = semantics.evaluate({
        "schema_version": semantics.INPUT_SCHEMA_VERSION,
        "operation_code": c["operation_code"],
        "phase": "CLOSURE",
        "contracts": [normalized],
        "facts": facts,
    })
    assert semantic_result["verdict"] == "READY"
    core_result = core.evaluate({
        "schema_version": core.SCHEMA_VERSION,
        "operation_code": c["operation_code"],
        "phase": "CLOSURE",
        "contracts": [normalized],
        "evaluations": semantic_result["evaluations"],
    })
    assert core_result["verdict"] == "PASS", core_result


CASES = [
    case_standard_full_ready,
    case_blocked_object_shape_ready,
    case_all_object_shape_ready,
    case_object_array_object_shape_ready,
    case_nested_object_atoms_are_explicit,
    case_partial_shadow_never_ready,
    case_full_incomplete_blocks,
    case_source_sha_drift_blocks,
    case_expected_source_mismatch_blocks,
    case_json_equality_is_type_strict,
    case_duplicate_source_mapping_blocks,
    case_duplicate_typed_id_blocks,
    case_non_atom_pointer_blocks,
    case_identity_mismatch_blocks,
    case_end_to_end_semantics_and_core_pass,
]


def main() -> None:
    passed = 0
    for case in CASES:
        case()
        passed += 1
    assert passed == len(CASES)
    print(f"PASS_LEGACY_CONTRACT_NORMALIZATION_V1={passed}/{len(CASES)}")


if __name__ == "__main__":
    main()
