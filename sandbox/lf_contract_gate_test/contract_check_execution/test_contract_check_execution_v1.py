#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "contract_check_execution_v1.py"


def load():
    spec = importlib.util.spec_from_file_location("contract_check_execution_v1_test", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load contract_check_execution_v1")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


execution = load()
PASS = 0
TOTAL = 0


def check(condition, label):
    global PASS, TOTAL
    TOTAL += 1
    if not condition:
        raise AssertionError(label)
    PASS += 1


def contract(code="C_TYPED", *, operation="OP_EXEC", status="ACTIVE_ENFORCEMENT"):
    return {
        "operation_code": operation,
        "contract_code": code,
        "contract_path": f"supabase://public/lf_operation_contracts/{operation}/{code}",
        "contract_sha": None,
        "required_before_write": [
            {"id": "contract_bound", "predicate": {"op": "TRUE", "fact": "contract.bound"}},
        ],
        "allowed": [
            {"id": "production_disabled", "predicate": {"op": "FALSE", "fact": "production.allowed"}},
        ],
        "blocked": [
            {"id": "runtime_enable", "predicate": {"op": "TRUE", "fact": "runtime.enable_requested"}},
        ],
        "required_after_write": [],
        "status": status,
    }


def facts():
    return {
        "contract.bound": {"present": True, "value": True, "evidence_refs": ["evidence://contract-bound"]},
        "production.allowed": {"present": True, "value": False, "evidence_refs": ["evidence://production-allowed"]},
        "runtime.enable_requested": {"present": True, "value": False, "evidence_refs": ["evidence://runtime-request"]},
    }


def packet():
    return {
        "schema_version": execution.SCHEMA_VERSION,
        "phase": "ENTRY",
        "operation_context": {
            "operation_code": "OP_EXEC",
            "authority_source": execution.CANONICAL_AUTHORITY_SOURCE,
            "authority_contracts": [
                contract(),
                contract("C_INACTIVE", status="INACTIVE"),
                contract("C_OTHER", operation="OP_OTHER"),
            ],
        },
        "bindings": [{"contract_code": "C_TYPED", "source_mode": "TYPED"}],
        "facts": facts(),
    }


def expect_input_error(mutator, fragment):
    p = packet()
    mutator(p)
    try:
        execution.run(p)
    except execution.ContractCheckExecutionInputError as exc:
        return fragment in str(exc)
    return False


def main():
    result = execution.run(packet())
    check(result["verdict"] == "PASS", "full chain PASS")
    check(result["stage"] == "COMPLETE", "full chain complete")
    check(result["operation_code"] == "OP_EXEC", "operation context preserved")
    check(result["counts"]["resolved_contracts"] == 1, "resolution filtered inactive and other operation")
    check(result["counts"]["typed_direct"] == 1, "explicit TYPED binding consumed")
    check(result["counts"]["normalized_legacy"] == 0, "no normalization inferred")
    check(result["core_result"]["verdict"] == "PASS", "core reached")

    blocked = packet()
    blocked["facts"]["runtime.enable_requested"]["value"] = True
    blocked_result = execution.run(blocked)
    check(blocked_result["verdict"] == "BLOCK", "contractual BLOCK propagated")
    check(blocked_result["stage"] == "CONTRACT_CHECK_CORE", "BLOCK attributed to core")

    multi = packet()
    multi["operation_context"]["authority_contracts"].append(contract("C_TYPED_2"))
    multi["bindings"].append({"contract_code": "C_TYPED_2", "source_mode": "TYPED"})
    multi_result = execution.run(multi)
    check(multi_result["verdict"] == "PASS", "multiple active contracts PASS")
    check(multi_result["counts"]["resolved_contracts"] == 2, "all active contracts resolved")

    missing = packet()
    missing["operation_context"]["authority_contracts"] = [contract("C_OTHER", operation="OP_OTHER")]
    try:
        execution.run(missing)
    except execution.RESOLUTION.CORE.ContractResolutionError as exc:
        check(str(exc) == "BLOCK_ACTIVE_CONTRACT_MISSING:OP_EXEC", "zero active fails closed")
    else:
        raise AssertionError("zero active contract did not block")

    check(expect_input_error(lambda p: p.update(schema_version="bad"), "schema_version_invalid"), "schema fail closed")
    check(expect_input_error(lambda p: p["operation_context"].update(operation_code=""), "operation_code_missing"), "operation required")
    check(expect_input_error(lambda p: p["operation_context"].update(authority_source="other"), "authority_source_invalid"), "authority source fixed")
    check(expect_input_error(lambda p: p.update(extra=True), "unexpected_top_level_keys"), "unexpected input rejected")

    drift = packet()
    drift["bindings"] = []
    drift_result = execution.run(drift)
    check(drift_result["verdict"] == "BLOCK" and drift_result["stage"] == "BINDINGS", "missing binding blocks")

    no_facts = packet()
    no_facts["facts"] = {}
    no_facts_result = execution.run(no_facts)
    check(no_facts_result["verdict"] == "BLOCK" and no_facts_result["stage"] == "PREDICATE_SEMANTICS", "missing evidence-backed facts block")

    assert TOTAL == 18, TOTAL
    print("PASS_CONTRACT_CHECK_EXECUTION_CHAIN_V1=18/18")


if __name__ == "__main__":
    main()
