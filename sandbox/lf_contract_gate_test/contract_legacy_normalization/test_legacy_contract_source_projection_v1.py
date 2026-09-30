#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "legacy_contract_normalization_v1.py"


def load():
    spec = importlib.util.spec_from_file_location("legacy_contract_normalization_source_projection_test", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load legacy_contract_normalization_v1")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


normalization = load()
PASS = 0
TOTAL = 0


def check(condition, label):
    global PASS, TOTAL
    TOTAL += 1
    if not condition:
        raise AssertionError(label)
    PASS += 1


def contract():
    return {
        "operation_code": "OP_SOURCE_PROJECTION",
        "contract_code": "CONTRACT-SOURCE-PROJECTION-v1",
        "contract_path": "supabase://public/lf_operation_contracts/OP_SOURCE_PROJECTION/v1",
        "contract_sha": None,
        "required_before_write": "precondition_ok",
        "allowed": True,
        "blocked": False,
        "required_after_write": "readback_ok",
        "status": "ACTIVE_ENFORCEMENT",
    }


def typed_term(term_id: str, fact: str):
    return {"id": term_id, "predicate": {"op": "TRUE", "fact": fact}}


def translation(source):
    projection = normalization._source_contract_projection(source)
    return {
        "schema_version": normalization.TRANSLATION_SCHEMA_VERSION,
        "operation_code": source["operation_code"],
        "contract_code": source["contract_code"],
        "source_contract_sha256": normalization._sha(projection),
        "coverage_mode": "FULL",
        "mappings": [
            {
                "section": "required_before_write",
                "source_pointer": "/required_before_write",
                "expected_source": source["required_before_write"],
                "typed_term": typed_term("precondition_ok", "precondition.ok"),
            },
            {
                "section": "allowed",
                "source_pointer": "/allowed",
                "expected_source": source["allowed"],
                "typed_term": typed_term("allowed", "operation.allowed"),
            },
            {
                "section": "blocked",
                "source_pointer": "/blocked",
                "expected_source": source["blocked"],
                "typed_term": typed_term("blocked", "operation.blocked"),
            },
            {
                "section": "required_after_write",
                "source_pointer": "/required_after_write",
                "expected_source": source["required_after_write"],
                "typed_term": typed_term("readback_ok", "readback.ok"),
            },
        ],
    }


def normalize(source, spec):
    return normalization.normalize(
        {
            "schema_version": normalization.INPUT_SCHEMA_VERSION,
            "legacy_contract": source,
            "translation": spec,
        }
    )


def expect_error(source, spec, fragment):
    try:
        normalize(source, spec)
    except normalization.LegacyContractNormalizationError as exc:
        return fragment in str(exc)
    return False


def main():
    base = contract()
    spec = translation(base)
    baseline = normalize(base, spec)
    check(baseline["ready_for_contract_check"] is True, "baseline ready")
    check(baseline["coverage"] == {"mode": "FULL", "source_atoms": 4, "covered_atoms": 4, "missing_atoms": []}, "four semantic atoms fully covered")

    with_audit = deepcopy(base)
    with_audit.update(
        {
            "created_at": "2026-09-29T20:00:00-05:00",
            "updated_at": "2026-09-29T20:05:00-05:00",
            "created_by_execution_id": "EXEC-CREATE",
            "updated_by_execution_id": "EXEC-UPDATE",
        }
    )
    audited = normalize(with_audit, spec)
    check(audited["ready_for_contract_check"] is True, "audit columns do not invalidate translation")
    check(audited["source_contract_sha256"] == baseline["source_contract_sha256"], "audit columns excluded from source digest")

    with_transport_metadata = deepcopy(with_audit)
    with_transport_metadata["snapshot_received_at"] = "2026-09-29T20:10:00-05:00"
    transported = normalize(with_transport_metadata, spec)
    check(transported["source_contract_sha256"] == baseline["source_contract_sha256"], "transport metadata excluded from source digest")

    semantic_drift = deepcopy(base)
    semantic_drift["allowed"] = False
    check(expect_error(semantic_drift, spec, "source_contract_sha256_mismatch"), "semantic section drift invalidates translation")

    status_drift = deepcopy(base)
    status_drift["status"] = "SUPERSEDED"
    check(expect_error(status_drift, spec, "source_contract_sha256_mismatch"), "status drift invalidates translation")

    missing_identity = deepcopy(base)
    del missing_identity["contract_path"]
    check(expect_error(missing_identity, spec, "source_binding_key_missing:contract_path"), "missing semantic identity fails closed")

    assert TOTAL == 8, TOTAL
    print("PASS_LEGACY_CONTRACT_SOURCE_PROJECTION_V1=8/8")


if __name__ == "__main__":
    main()
