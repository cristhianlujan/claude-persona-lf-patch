#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "legacy_contract_normalization_v1.py"


def load():
    spec = importlib.util.spec_from_file_location("legacy_contract_grouped_mapping_test", MODULE_PATH)
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
        "operation_code": "OP_GROUPED_MAPPING",
        "contract_code": "CONTRACT-GROUPED-MAPPING-v1",
        "contract_path": "supabase://public/lf_operation_contracts/OP_GROUPED_MAPPING/v1",
        "contract_sha": None,
        "required_before_write": ["router_read", "contract_read"],
        "allowed": {"execution_modes": ["READ_ONLY", "SANDBOX"]},
        "blocked": ["production_enable"],
        "required_after_write": ["exact_readback"],
        "status": "ACTIVE_ENFORCEMENT",
    }


def term(term_id, predicate):
    return {"id": term_id, "predicate": predicate}


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
                "source_pointer": "/required_before_write/0",
                "expected_source": "router_read",
                "typed_term": term("router_read", {"op": "TRUE", "fact": "router.read"}),
            },
            {
                "section": "required_before_write",
                "source_pointer": "/required_before_write/1",
                "expected_source": "contract_read",
                "typed_term": term("contract_read", {"op": "TRUE", "fact": "contract.read"}),
            },
            {
                "section": "allowed",
                "source_pointer": "/allowed/execution_modes",
                "expected_source": ["READ_ONLY", "SANDBOX"],
                "typed_term": term(
                    "execution_mode_allowed",
                    {"op": "IN", "fact": "execution.mode", "values": ["READ_ONLY", "SANDBOX"]},
                ),
            },
            {
                "section": "blocked",
                "source_pointer": "/blocked/0",
                "expected_source": "production_enable",
                "typed_term": term("production_enable", {"op": "TRUE", "fact": "production.enable"}),
            },
            {
                "section": "required_after_write",
                "source_pointer": "/required_after_write/0",
                "expected_source": "exact_readback",
                "typed_term": term("exact_readback", {"op": "TRUE", "fact": "readback.exact"}),
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
    source = contract()
    spec = translation(source)
    result = normalize(source, spec)

    check(result["ready_for_contract_check"] is True, "grouped mapping ready")
    check(result["coverage"]["source_atoms"] == 6, "six legacy leaf atoms")
    check(result["coverage"]["covered_atoms"] == 6, "grouped node covers both array descendants")
    check(result["coverage"]["missing_atoms"] == [], "no coverage gap")
    check(len(result["normalized_contract"]["allowed"]) == 1, "allowed set becomes one typed term")
    check(result["normalized_contract"]["allowed"][0]["predicate"]["op"] == "IN", "set semantics preserved explicitly")

    overlap = deepcopy(spec)
    overlap["mappings"].append(
        {
            "section": "allowed",
            "source_pointer": "/allowed/execution_modes/0",
            "expected_source": "READ_ONLY",
            "typed_term": term("read_only_duplicate", {"op": "TRUE", "fact": "execution.read_only"}),
        }
    )
    check(expect_error(source, overlap, "duplicate_source_mapping:/allowed/execution_modes/0"), "overlapping grouped and leaf mapping fails closed")

    wrong_node = deepcopy(spec)
    wrong_node["mappings"][2]["expected_source"] = ["READ_ONLY"]
    check(expect_error(source, wrong_node, "mapping_source_value_mismatch:/allowed/execution_modes"), "group expected source bound exactly")

    cross_section = deepcopy(spec)
    cross_section["mappings"][2]["section"] = "blocked"
    check(expect_error(source, cross_section, "mapping_section_pointer_mismatch"), "group cannot cross section boundary")

    assert TOTAL == 9, TOTAL
    print("PASS_LEGACY_CONTRACT_GROUPED_SOURCE_MAPPING_V1=9/9")


if __name__ == "__main__":
    main()
