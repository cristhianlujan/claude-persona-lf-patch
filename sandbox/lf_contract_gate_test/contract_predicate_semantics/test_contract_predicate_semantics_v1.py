#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "contract_predicate_semantics_v1.py"
CORE_PATH = HERE.parent / "contract_check_core" / "contract_check_core_v1.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


sem = load(MODULE_PATH, "contract_predicate_semantics_v1_test")
core = load(CORE_PATH, "contract_check_core_v1_for_predicate_test")

PASS = 0
TOTAL = 0


def check(condition, label):
    global PASS, TOTAL
    TOTAL += 1
    if not condition:
        raise AssertionError(label)
    PASS += 1


def typed_contract():
    return {
        "operation_code": "OP_TYPED_TEST",
        "contract_code": "CONTRACT-OP-TYPED-v1",
        "contract_path": "supabase://public/lf_operation_contracts/OP_TYPED_TEST/typed-v1",
        "contract_sha": None,
        "required_before_write": [
            {
                "id": "contract_bound",
                "predicate": {"op": "TRUE", "fact": "contract.bound"},
            },
            {
                "id": "mode_supported",
                "predicate": {"op": "IN", "fact": "execution.mode", "values": ["READ_ONLY", "SANDBOX"]},
            },
            {
                "id": "optional_scope",
                "applies_when": {"op": "TRUE", "fact": "scope.applicable"},
                "predicate": {"op": "EQ", "fact": "scope.name", "value": "PROFILE"},
            },
        ],
        "allowed": [
            {
                "id": "production_disabled",
                "predicate": {"op": "FALSE", "fact": "production.allowed"},
            },
            {
                "id": "safe_composite",
                "predicate": {
                    "op": "ALL",
                    "args": [
                        {"op": "TRUE", "fact": "contract.bound"},
                        {"op": "NOT", "arg": {"op": "TRUE", "fact": "write.bypass"}},
                    ],
                },
            },
        ],
        "blocked": [
            {
                "id": "runtime_enable",
                "predicate": {"op": "TRUE", "fact": "runtime.enable_requested"},
            },
            {
                "id": "forbidden_mode",
                "predicate": {"op": "EQ", "fact": "execution.mode", "value": "PRODUCTION"},
            },
        ],
        "required_after_write": [
            {
                "id": "readback_present",
                "predicate": {"op": "EXISTS", "fact": "readback.sha"},
            }
        ],
    }


def facts():
    def obs(value=None, *, present=True, ref=None):
        row = {
            "present": present,
            "evidence_refs": [ref or f"evidence://{len(str(value))}/{str(value).lower()}"],
        }
        if present:
            row["value"] = value
        return row

    return {
        "contract.bound": obs(True, ref="evidence://contract-bound"),
        "execution.mode": obs("READ_ONLY", ref="evidence://execution-mode"),
        "scope.applicable": obs(False, ref="evidence://scope-applicability"),
        "scope.name": obs("PROFILE", ref="evidence://scope-name"),
        "production.allowed": obs(False, ref="evidence://production-allowed"),
        "write.bypass": obs(False, ref="evidence://write-bypass"),
        "runtime.enable_requested": obs(False, ref="evidence://runtime-request"),
        "readback.sha": obs("abc123", ref="evidence://readback"),
        "artifact.missing": {"present": False, "evidence_refs": ["evidence://artifact-absence"]},
    }


def packet(phase="ENTRY"):
    return {
        "schema_version": sem.INPUT_SCHEMA_VERSION,
        "operation_code": "OP_TYPED_TEST",
        "phase": phase,
        "contracts": [typed_contract()],
        "facts": facts(),
    }


def by_semantic(result, semantic_id):
    contract = typed_contract()
    mapping = {}
    for section in sem.SECTIONS_BY_PHASE[result["phase"]]:
        for i, term in enumerate(contract[section]):
            mapping[term["id"]] = f"{section}[{i}]"
    target = mapping[semantic_id]
    return next(e for e in result["evaluations"] if e["term_id"] == target)


def expect_input_error(mutator, code_fragment):
    p = packet()
    mutator(p)
    try:
        sem.evaluate(p)
    except sem.ContractPredicateSemanticsInputError as exc:
        return code_fragment in str(exc)
    return False


def main():
    result = sem.evaluate(packet())
    check(result["verdict"] == "READY", "entry semantics ready")
    check(result["counts"] == {"resolved_contracts": 1, "evaluations": 7, "failures": 0}, "entry counts")
    check(by_semantic(result, "contract_bound")["verdict"] == "SATISFIED", "TRUE satisfied")
    check(by_semantic(result, "mode_supported")["verdict"] == "SATISFIED", "IN satisfied")
    check(by_semantic(result, "optional_scope")["verdict"] == "NOT_APPLICABLE", "applies_when N/A")
    check(by_semantic(result, "optional_scope")["rationale"] == "applies_when_false:optional_scope", "N/A rationale")
    check(by_semantic(result, "production_disabled")["verdict"] == "SATISFIED", "FALSE satisfied")
    check(by_semantic(result, "safe_composite")["verdict"] == "SATISFIED", "ALL NOT satisfied")
    check(by_semantic(result, "runtime_enable")["verdict"] == "CLEAR", "blocked clear")
    check(by_semantic(result, "forbidden_mode")["verdict"] == "CLEAR", "blocked EQ clear")
    check(all(e["evidence_refs"] for e in result["evaluations"]), "all evaluations evidenced")

    core_result = core.evaluate(
        {
            "schema_version": core.SCHEMA_VERSION,
            "operation_code": "OP_TYPED_TEST",
            "phase": "ENTRY",
            "contracts": packet()["contracts"],
            "evaluations": result["evaluations"],
        }
    )
    check(core_result["verdict"] == "PASS", "semantic output accepted by core")

    p = packet()
    p["facts"]["runtime.enable_requested"]["value"] = True
    triggered = sem.evaluate(p)
    check(triggered["verdict"] == "READY", "triggered predicate still semantically ready")
    check(by_semantic(triggered, "runtime_enable")["verdict"] == "TRIGGERED", "blocked term triggered")
    core_triggered = core.evaluate(
        {
            "schema_version": core.SCHEMA_VERSION,
            "operation_code": "OP_TYPED_TEST",
            "phase": "ENTRY",
            "contracts": p["contracts"],
            "evaluations": triggered["evaluations"],
        }
    )
    check(core_triggered["verdict"] == "BLOCK", "core blocks triggered term")

    p = packet()
    p["facts"]["contract.bound"]["value"] = False
    failed = sem.evaluate(p)
    check(by_semantic(failed, "contract_bound")["verdict"] == "FAILED", "required false -> failed")
    core_failed = core.evaluate(
        {
            "schema_version": core.SCHEMA_VERSION,
            "operation_code": "OP_TYPED_TEST",
            "phase": "ENTRY",
            "contracts": p["contracts"],
            "evaluations": failed["evaluations"],
        }
    )
    check(core_failed["verdict"] == "BLOCK", "core blocks failed required term")

    closure = sem.evaluate(packet("CLOSURE"))
    check(closure["counts"]["evaluations"] == 8, "closure includes after-write")
    after = next(e for e in closure["evaluations"] if e["section"] == "required_after_write")
    check(after["verdict"] == "SATISFIED", "EXISTS after-write satisfied")

    p = packet("CLOSURE")
    p["facts"]["readback.sha"]["present"] = False
    p["facts"]["readback.sha"].pop("value")
    absent_readback = sem.evaluate(p)
    after = next(e for e in absent_readback["evaluations"] if e["section"] == "required_after_write")
    check(after["verdict"] == "FAILED", "EXISTS false when explicitly absent")

    c = typed_contract()
    c["required_before_write"].append(
        {"id": "artifact_absent", "predicate": {"op": "ABSENT", "fact": "artifact.missing"}}
    )
    p = packet()
    p["contracts"] = [c]
    absent = sem.evaluate(p)
    check(absent["verdict"] == "READY", "ABSENT explicit observation ready")
    absent_eval = next(e for e in absent["evaluations"] if e["term_id"] == "required_before_write[3]")
    check(absent_eval["verdict"] == "SATISFIED", "ABSENT evaluated")

    p = packet()
    del p["facts"]["contract.bound"]
    missing = sem.evaluate(p)
    check(missing["verdict"] == "BLOCK", "missing observation fail closed")
    check(any(f["code"] == "FAIL_FACT_OBSERVATION_MISSING" for f in missing["failures"]), "missing fact code")

    p = packet()
    p["facts"]["contract.bound"]["evidence_refs"] = []
    no_evidence = sem.evaluate(p)
    check(no_evidence["verdict"] == "BLOCK", "missing evidence fail closed")
    check(any(f["code"] == "FAIL_FACT_EVIDENCE_MISSING" for f in no_evidence["failures"]), "missing evidence code")

    p = packet()
    p["facts"]["contract.bound"]["value"] = "yes"
    wrong_bool = sem.evaluate(p)
    check(wrong_bool["verdict"] == "BLOCK", "TRUE requires boolean")
    check(any(f["code"] == "FAIL_FACT_BOOLEAN_REQUIRED" for f in wrong_bool["failures"]), "boolean type code")

    p = packet()
    p["contracts"][0]["allowed"] = {"production_disabled": False}
    shape = sem.evaluate(p)
    check(shape["verdict"] == "BLOCK", "legacy object section rejected by typed evaluator")
    check(any(f["code"] == "FAIL_TYPED_SECTION_REQUIRED" for f in shape["failures"]), "typed section code")

    p = packet()
    duplicate = deepcopy(p["contracts"][0]["blocked"][0])
    p["contracts"][0]["blocked"].append(duplicate)
    dup = sem.evaluate(p)
    check(dup["verdict"] == "BLOCK", "duplicate semantic id blocked")
    check(any(f["code"] == "FAIL_SEMANTIC_TERM_ID_DUPLICATE" for f in dup["failures"]), "duplicate id code")

    check(expect_input_error(lambda p: p.__setitem__("phase", "WRITE"), "phase_invalid"), "invalid phase rejected")

    p = packet()
    p["contracts"][0]["required_before_write"][0]["predicate"] = {"op": "PYTHON", "fact": "contract.bound"}
    invalid_op = sem.evaluate(p)
    check(invalid_op["verdict"] == "BLOCK", "unknown operator fail closed")
    check(
        any(f["code"] == "FAIL_TYPED_TERM_SCHEMA" and "predicate_operator_invalid" in f["detail"]["reason"] for f in invalid_op["failures"]),
        "unknown operator rejected",
    )

    p = packet()
    p["contracts"][0]["required_before_write"][0]["predicate"] = {"op": "TRUE", "fact": "contract.bound", "eval": "x"}
    extra_key = sem.evaluate(p)
    check(
        any(f["code"] == "FAIL_TYPED_TERM_SCHEMA" and "predicate_unexpected_keys" in f["detail"]["reason"] for f in extra_key["failures"]),
        "predicate extra keys rejected",
    )

    p = packet()
    p["contracts"][0]["required_before_write"][0]["predicate"] = {"op": "ALL", "args": []}
    empty_all = sem.evaluate(p)
    check(
        any(f["code"] == "FAIL_TYPED_TERM_SCHEMA" and "predicate_args_empty" in f["detail"]["reason"] for f in empty_all["failures"]),
        "empty ALL rejected",
    )

    c = typed_contract()
    c["required_before_write"] = [
        {"id": "neq", "predicate": {"op": "NEQ", "fact": "execution.mode", "value": "PRODUCTION"}},
        {"id": "not_in", "predicate": {"op": "NOT_IN", "fact": "execution.mode", "values": ["PRODUCTION", "UNSAFE"]}},
        {
            "id": "any",
            "predicate": {
                "op": "ANY",
                "args": [
                    {"op": "EQ", "fact": "execution.mode", "value": "READ_ONLY"},
                    {"op": "TRUE", "fact": "runtime.enable_requested"},
                ],
            },
        },
    ]
    c["allowed"] = []
    c["blocked"] = []
    p = packet()
    p["contracts"] = [c]
    extra_ops = sem.evaluate(p)
    check(extra_ops["verdict"] == "READY", "NEQ NOT_IN ANY ready")
    check([e["verdict"] for e in extra_ops["evaluations"]] == ["SATISFIED", "SATISFIED", "SATISFIED"], "NEQ NOT_IN ANY semantics")

    c = typed_contract()
    c["required_before_write"] = [
        {"id": "strict_eq", "predicate": {"op": "EQ", "fact": "contract.bound", "value": 1}},
        {"id": "strict_in", "predicate": {"op": "IN", "fact": "contract.bound", "values": [1, 2]}},
    ]
    c["allowed"] = []
    c["blocked"] = []
    p = packet()
    p["contracts"] = [c]
    strict_types = sem.evaluate(p)
    check(strict_types["verdict"] == "READY", "strict JSON type comparison ready")
    check(
        [e["verdict"] for e in strict_types["evaluations"]] == ["FAILED", "FAILED"],
        "boolean never equals numeric JSON values",
    )

    p = packet()
    p["facts"]["contract.bound"]["present"] = False
    p["facts"]["contract.bound"]["value"] = "ambiguous"
    absent_with_value = sem.evaluate(p)
    check(absent_with_value["verdict"] == "BLOCK", "absent observation with value blocked")
    check(
        any(f["code"] == "FAIL_FACT_ABSENT_WITH_VALUE" for f in absent_with_value["failures"]),
        "absent observation ambiguity code",
    )

    check(PASS == TOTAL, "pass counter consistent")
    print(f"PASS_CONTRACT_PREDICATE_SEMANTICS_V1={PASS}/{TOTAL}")


if __name__ == "__main__":
    main()
