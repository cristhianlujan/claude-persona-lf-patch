#!/usr/bin/env python3
from __future__ import annotations

import copy
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_resolution"))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_legacy_normalization"))

import contract_check_semantic_integration_v1 as integration
import contract_resolution_core_v1 as resolver
import legacy_contract_normalization_v1 as normalization


def facts() -> dict[str, Any]:
    return {
        "ready": {"present": True, "value": True, "evidence_refs": ["evidence://ready"]},
        "mode": {"present": True, "value": "READ_ONLY", "evidence_refs": ["evidence://mode"]},
        "runtime_enable_requested": {"present": True, "value": False, "evidence_refs": ["evidence://runtime"]},
        "prod": {"present": True, "value": False, "evidence_refs": ["evidence://prod"]},
        "readback": {"present": True, "value": True, "evidence_refs": ["evidence://readback"]},
    }


def typed_row(code: str = "CONTRACT-TYPED-v1", op: str = "SAMPLE_OP") -> dict[str, Any]:
    return {
        "operation_code": op,
        "contract_code": code,
        "contract_path": f"supabase://contracts/{code}",
        "contract_sha": "a" * 64,
        "required_before_write": [{"id": "ready", "predicate": {"op": "TRUE", "fact": "ready"}}],
        "allowed": [{"id": "mode", "predicate": {"op": "EQ", "fact": "mode", "value": "READ_ONLY"}}],
        "blocked": [{"id": "production", "predicate": {"op": "TRUE", "fact": "prod"}}],
        "required_after_write": [{"id": "readback", "predicate": {"op": "TRUE", "fact": "readback"}}],
        "status": "ACTIVE_ENFORCEMENT",
    }


def legacy_row(code: str = "CONTRACT-LEGACY-v1", op: str = "SAMPLE_OP") -> dict[str, Any]:
    return {
        "operation_code": op,
        "contract_code": code,
        "contract_path": f"supabase://contracts/{code}",
        "contract_sha": "b" * 64,
        "required_before_write": ["router_read"],
        "allowed": {"runtime_enable": False},
        "blocked": ["production_enable"],
        "required_after_write": ["exact_readback"],
        "status": "ACTIVE_ENFORCEMENT",
    }


def legacy_mappings() -> list[dict[str, Any]]:
    return [
        {
            "section": "required_before_write",
            "source_pointer": "/required_before_write/0",
            "expected_source": "router_read",
            "typed_term": {"id": "router_read", "predicate": {"op": "TRUE", "fact": "ready"}},
        },
        {
            "section": "allowed",
            "source_pointer": "/allowed/runtime_enable",
            "expected_source": False,
            "typed_term": {"id": "runtime_disabled", "predicate": {"op": "FALSE", "fact": "runtime_enable_requested"}},
        },
        {
            "section": "blocked",
            "source_pointer": "/blocked/0",
            "expected_source": "production_enable",
            "typed_term": {"id": "production_enable", "predicate": {"op": "TRUE", "fact": "prod"}},
        },
        {
            "section": "required_after_write",
            "source_pointer": "/required_after_write/0",
            "expected_source": "exact_readback",
            "typed_term": {"id": "exact_readback", "predicate": {"op": "TRUE", "fact": "readback"}},
        },
    ]


def legacy_translation(row: dict[str, Any], *, mode: str = "FULL", mappings: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {
        "schema_version": normalization.TRANSLATION_SCHEMA_VERSION,
        "operation_code": row["operation_code"],
        "contract_code": row["contract_code"],
        "source_contract_sha256": normalization._sha(row),
        "coverage_mode": mode,
        "mappings": copy.deepcopy(legacy_mappings() if mappings is None else mappings),
    }


def resolve(rows: list[dict[str, Any]], op: str = "SAMPLE_OP") -> dict[str, Any]:
    return resolver.resolve_contracts(operation_code=op, contracts=rows)


def reseal(resolution: dict[str, Any]) -> None:
    unsigned = dict(resolution)
    unsigned.pop("resolution_sha256", None)
    resolution["resolution_sha256"] = resolver._sha256(unsigned)


def packet(resolution: dict[str, Any], bindings: list[dict[str, Any]], *, phase: str = "CLOSURE", fact_map: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "schema_version": integration.INPUT_SCHEMA_VERSION,
        "phase": phase,
        "resolution": resolution,
        "bindings": bindings,
        "facts": facts() if fact_map is None else fact_map,
    }


def codes(result: dict[str, Any]) -> set[str]:
    return {entry["code"] for entry in result["failures"]}


def expect_input_error(fn, token: str) -> None:
    try:
        fn()
    except integration.ContractCheckSemanticIntegrationInputError as exc:
        assert token in str(exc), (token, str(exc))
        return
    raise AssertionError(f"expected input error containing {token}")


def case_legacy_pass() -> None:
    row = legacy_row()
    result = integration.evaluate(packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "LEGACY_TRANSLATION", "translation": legacy_translation(row)}]))
    assert result["verdict"] == "PASS", result
    assert result["stage"] == "COMPLETE"
    assert result["counts"]["normalized_legacy"] == 1


def case_typed_pass() -> None:
    row = typed_row()
    result = integration.evaluate(packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "TYPED"}]))
    assert result["verdict"] == "PASS", result
    assert result["counts"]["typed_direct"] == 1


def case_mixed_pass() -> None:
    typed = typed_row("CONTRACT-B-TYPED-v1")
    legacy = legacy_row("CONTRACT-A-LEGACY-v1")
    bindings = [
        {"contract_code": typed["contract_code"], "source_mode": "TYPED"},
        {"contract_code": legacy["contract_code"], "source_mode": "LEGACY_TRANSLATION", "translation": legacy_translation(legacy)},
    ]
    result = integration.evaluate(packet(resolve([typed, legacy]), bindings))
    assert result["verdict"] == "PASS", result
    assert result["counts"]["resolved_contracts"] == 2
    assert result["counts"]["typed_direct"] == 1
    assert result["counts"]["normalized_legacy"] == 1


def case_required_false_blocks_in_core() -> None:
    row = typed_row()
    f = facts()
    f["ready"]["value"] = False
    result = integration.evaluate(packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "TYPED"}], fact_map=f))
    assert result["verdict"] == "BLOCK"
    assert result["stage"] == "CONTRACT_CHECK_CORE"
    assert "FAIL_CONTRACT_TERM_NOT_SATISFIED" in codes(result)


def case_blocked_triggered_blocks_in_core() -> None:
    row = typed_row()
    f = facts()
    f["prod"]["value"] = True
    result = integration.evaluate(packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "TYPED"}], fact_map=f))
    assert result["verdict"] == "BLOCK"
    assert result["stage"] == "CONTRACT_CHECK_CORE"
    assert "FAIL_CONTRACT_TERM_NOT_SATISFIED" in codes(result)


def case_missing_fact_blocks_in_semantics() -> None:
    row = typed_row()
    f = facts()
    f.pop("readback")
    result = integration.evaluate(packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "TYPED"}], fact_map=f))
    assert result["verdict"] == "BLOCK"
    assert result["stage"] == "PREDICATE_SEMANTICS"
    assert "FAIL_FACT_OBSERVATION_MISSING" in codes(result)


def case_partial_legacy_blocks() -> None:
    row = legacy_row()
    translation = legacy_translation(row, mode="PARTIAL_SHADOW", mappings=legacy_mappings()[:2])
    result = integration.evaluate(packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "LEGACY_TRANSLATION", "translation": translation}]))
    assert result["verdict"] == "BLOCK"
    assert result["stage"] == "NORMALIZATION"
    assert "FAIL_LEGACY_NORMALIZATION_NOT_READY" in codes(result)


def case_translation_source_drift_blocks() -> None:
    original = legacy_row()
    translation = legacy_translation(original)
    drifted = copy.deepcopy(original)
    drifted["allowed"]["runtime_enable"] = True
    result = integration.evaluate(packet(resolve([drifted]), [{"contract_code": drifted["contract_code"], "source_mode": "LEGACY_TRANSLATION", "translation": translation}]))
    assert result["verdict"] == "BLOCK"
    assert result["stage"] == "NORMALIZATION"
    assert "FAIL_LEGACY_NORMALIZATION" in codes(result)


def case_binding_missing_blocks() -> None:
    row = typed_row()
    result = integration.evaluate(packet(resolve([row]), []))
    assert result["stage"] == "BINDINGS"
    assert "FAIL_BINDING_MISSING" in codes(result)


def case_binding_extra_blocks() -> None:
    row = typed_row()
    bindings = [
        {"contract_code": row["contract_code"], "source_mode": "TYPED"},
        {"contract_code": "CONTRACT-EXTRA-v1", "source_mode": "TYPED"},
    ]
    result = integration.evaluate(packet(resolve([row]), bindings))
    assert result["stage"] == "BINDINGS"
    assert "FAIL_BINDING_UNDECLARED" in codes(result)


def case_binding_duplicate_blocks() -> None:
    row = typed_row()
    binding = {"contract_code": row["contract_code"], "source_mode": "TYPED"}
    result = integration.evaluate(packet(resolve([row]), [binding, copy.deepcopy(binding)]))
    assert result["stage"] == "BINDINGS"
    assert "FAIL_BINDING_DUPLICATE" in codes(result)


def case_resolution_sha_mismatch_blocks() -> None:
    row = typed_row()
    resolution = resolve([row])
    resolution["resolution_sha256"] = "0" * 64
    result = integration.evaluate(packet(resolution, [{"contract_code": row["contract_code"], "source_mode": "TYPED"}]))
    assert result["stage"] == "RESOLUTION"
    assert "FAIL_RESOLUTION_SHA256_MISMATCH" in codes(result)


def case_resolution_count_mismatch_blocks() -> None:
    row = typed_row()
    resolution = resolve([row])
    resolution["contract_count"] = 2
    reseal(resolution)
    result = integration.evaluate(packet(resolution, [{"contract_code": row["contract_code"], "source_mode": "TYPED"}]))
    assert result["stage"] == "RESOLUTION"
    assert "FAIL_RESOLUTION_CONTRACT_COUNT" in codes(result)


def case_resolution_contract_operation_mismatch_blocks() -> None:
    row = typed_row()
    resolution = resolve([row])
    resolution["resolved_contracts"][0]["operation_code"] = "OTHER_OP"
    reseal(resolution)
    result = integration.evaluate(packet(resolution, [{"contract_code": row["contract_code"], "source_mode": "TYPED"}]))
    assert result["stage"] == "RESOLUTION"
    assert "FAIL_RESOLUTION_CONTRACT_OPERATION_MISMATCH" in codes(result)


def case_upstream_evaluations_forbidden() -> None:
    row = typed_row()
    p = packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "TYPED"}])
    p["evaluations"] = [{"verdict": "SATISFIED"}]
    expect_input_error(lambda: integration.evaluate(p), "unexpected_top_level_keys:evaluations")


def case_typed_binding_translation_forbidden() -> None:
    row = typed_row()
    binding = {"contract_code": row["contract_code"], "source_mode": "TYPED", "translation": {}}
    result = integration.evaluate(packet(resolve([row]), [binding]))
    assert result["stage"] == "BINDINGS"
    assert "FAIL_TYPED_BINDING_TRANSLATION_FORBIDDEN" in codes(result)


def case_legacy_binding_translation_required() -> None:
    row = legacy_row()
    binding = {"contract_code": row["contract_code"], "source_mode": "LEGACY_TRANSLATION"}
    result = integration.evaluate(packet(resolve([row]), [binding]))
    assert result["stage"] == "BINDINGS"
    assert "FAIL_LEGACY_BINDING_TRANSLATION_REQUIRED" in codes(result)


def case_phase_invalid_rejected() -> None:
    row = typed_row()
    p = packet(resolve([row]), [{"contract_code": row["contract_code"], "source_mode": "TYPED"}], phase="OTHER")
    expect_input_error(lambda: integration.evaluate(p), "phase_invalid")


CASES = [
    case_legacy_pass,
    case_typed_pass,
    case_mixed_pass,
    case_required_false_blocks_in_core,
    case_blocked_triggered_blocks_in_core,
    case_missing_fact_blocks_in_semantics,
    case_partial_legacy_blocks,
    case_translation_source_drift_blocks,
    case_binding_missing_blocks,
    case_binding_extra_blocks,
    case_binding_duplicate_blocks,
    case_resolution_sha_mismatch_blocks,
    case_resolution_count_mismatch_blocks,
    case_resolution_contract_operation_mismatch_blocks,
    case_upstream_evaluations_forbidden,
    case_typed_binding_translation_forbidden,
    case_legacy_binding_translation_required,
    case_phase_invalid_rejected,
]


def main() -> None:
    passed = 0
    for case in CASES:
        case()
        passed += 1
    assert passed == 18
    print(f"PASS_CONTRACT_CHECK_SEMANTIC_INTEGRATION_V1={passed}/{len(CASES)}")


if __name__ == "__main__":
    main()
