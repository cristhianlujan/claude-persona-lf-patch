#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from typing import Any, Mapping

INPUT_SCHEMA_VERSION = "lf-contract-predicate-semantics-input/v1"
RESULT_SCHEMA_VERSION = "lf-contract-predicate-semantics-result/v1"
SECTIONS_BY_PHASE = {
    "ENTRY": ("required_before_write", "allowed", "blocked"),
    "CLOSURE": ("required_before_write", "allowed", "blocked", "required_after_write"),
}
SUPPORTED_OPERATORS = frozenset(
    {"EXISTS", "ABSENT", "EQ", "NEQ", "IN", "NOT_IN", "TRUE", "FALSE", "ALL", "ANY", "NOT"}
)
_FACT_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]{0,127}$")
_TERM_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")


class ContractPredicateSemanticsInputError(ValueError):
    pass


def _obj(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ContractPredicateSemanticsInputError(f"{label}_must_be_object")
    return value


def _arr(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ContractPredicateSemanticsInputError(f"{label}_must_be_array")
    return value


def _text(row: Mapping[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else ""


def _canon(value: Any) -> str:
    try:
        return json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        raise ContractPredicateSemanticsInputError("non_json_value") from exc


def _sha(value: Any) -> str:
    return hashlib.sha256(_canon(value).encode("utf-8")).hexdigest()


def _json_equal(left: Any, right: Any) -> bool:
    return _canon(left) == _canon(right)


def _fact_name(value: Any) -> str:
    if not isinstance(value, str) or _FACT_RE.fullmatch(value) is None:
        raise ContractPredicateSemanticsInputError("predicate_fact_invalid")
    return value


def _term_id(value: Any) -> str:
    if not isinstance(value, str) or _TERM_ID_RE.fullmatch(value) is None:
        raise ContractPredicateSemanticsInputError("term_id_invalid")
    return value


def _keys_exact(node: Mapping[str, Any], allowed: set[str], label: str) -> None:
    extra = sorted(set(node) - allowed)
    if extra:
        raise ContractPredicateSemanticsInputError(f"{label}_unexpected_keys:{','.join(extra)}")


def _validate_predicate(node: Any) -> Mapping[str, Any]:
    pred = _obj(node, "predicate")
    op = _text(pred, "op")
    if op not in SUPPORTED_OPERATORS:
        raise ContractPredicateSemanticsInputError(f"predicate_operator_invalid:{op or '<missing>'}")

    if op in {"EXISTS", "ABSENT", "TRUE", "FALSE"}:
        _keys_exact(pred, {"op", "fact"}, "predicate")
        _fact_name(pred.get("fact"))
    elif op in {"EQ", "NEQ"}:
        _keys_exact(pred, {"op", "fact", "value"}, "predicate")
        _fact_name(pred.get("fact"))
        if "value" not in pred:
            raise ContractPredicateSemanticsInputError("predicate_value_missing")
        _canon(pred["value"])
    elif op in {"IN", "NOT_IN"}:
        _keys_exact(pred, {"op", "fact", "values"}, "predicate")
        _fact_name(pred.get("fact"))
        values = _arr(pred.get("values"), "predicate_values")
        if not values:
            raise ContractPredicateSemanticsInputError("predicate_values_empty")
        for value in values:
            _canon(value)
    elif op in {"ALL", "ANY"}:
        _keys_exact(pred, {"op", "args"}, "predicate")
        args = _arr(pred.get("args"), "predicate_args")
        if not args:
            raise ContractPredicateSemanticsInputError("predicate_args_empty")
        for arg in args:
            _validate_predicate(arg)
    elif op == "NOT":
        _keys_exact(pred, {"op", "arg"}, "predicate")
        if "arg" not in pred:
            raise ContractPredicateSemanticsInputError("predicate_arg_missing")
        _validate_predicate(pred["arg"])
    return pred


def _observation(
    observations: Mapping[str, Any], fact: str
) -> tuple[bool | None, Any, list[str], dict[str, Any] | None]:
    if fact not in observations:
        return None, None, [], {"code": "FAIL_FACT_OBSERVATION_MISSING", "detail": {"fact": fact}}
    row = observations[fact]
    if not isinstance(row, Mapping):
        return None, None, [], {"code": "FAIL_FACT_OBSERVATION_INVALID", "detail": {"fact": fact}}
    if set(row) - {"present", "value", "evidence_refs"}:
        return None, None, [], {"code": "FAIL_FACT_OBSERVATION_SHAPE", "detail": {"fact": fact}}
    if not isinstance(row.get("present"), bool):
        return None, None, [], {"code": "FAIL_FACT_PRESENT_FLAG", "detail": {"fact": fact}}
    refs = row.get("evidence_refs")
    if not isinstance(refs, list) or not refs or any(not isinstance(v, str) or not v.strip() for v in refs):
        return None, None, [], {"code": "FAIL_FACT_EVIDENCE_MISSING", "detail": {"fact": fact}}
    refs_norm = sorted({v.strip() for v in refs})
    present = bool(row["present"])
    if present and "value" not in row:
        return None, None, refs_norm, {"code": "FAIL_FACT_VALUE_MISSING", "detail": {"fact": fact}}
    if not present and "value" in row:
        return None, None, refs_norm, {"code": "FAIL_FACT_ABSENT_WITH_VALUE", "detail": {"fact": fact}}
    value = row.get("value")
    try:
        _canon(value)
    except ContractPredicateSemanticsInputError:
        return None, None, refs_norm, {"code": "FAIL_FACT_VALUE_NON_JSON", "detail": {"fact": fact}}
    return present, value, refs_norm, None


def _merge_refs(groups: list[list[str]]) -> list[str]:
    return sorted({ref for group in groups for ref in group})


def _eval_predicate(
    node: Mapping[str, Any], observations: Mapping[str, Any]
) -> tuple[bool | None, list[str], list[dict[str, Any]]]:
    op = _text(node, "op")
    if op in {"ALL", "ANY"}:
        results: list[bool] = []
        refs: list[list[str]] = []
        failures: list[dict[str, Any]] = []
        for arg in node["args"]:
            result, child_refs, child_failures = _eval_predicate(arg, observations)
            refs.append(child_refs)
            failures.extend(child_failures)
            if result is not None:
                results.append(result)
        if failures:
            return None, _merge_refs(refs), failures
        return (all(results) if op == "ALL" else any(results)), _merge_refs(refs), []
    if op == "NOT":
        result, refs, failures = _eval_predicate(node["arg"], observations)
        if failures or result is None:
            return None, refs, failures
        return (not result), refs, []

    fact = _fact_name(node.get("fact"))
    present, value, refs, failure = _observation(observations, fact)
    if failure is not None:
        return None, refs, [failure]

    if op == "EXISTS":
        return bool(present), refs, []
    if op == "ABSENT":
        return not bool(present), refs, []
    if not present:
        return False, refs, []
    if op == "EQ":
        return _json_equal(value, node["value"]), refs, []
    if op == "NEQ":
        return not _json_equal(value, node["value"]), refs, []
    if op == "IN":
        return any(_json_equal(value, candidate) for candidate in node["values"]), refs, []
    if op == "NOT_IN":
        return all(not _json_equal(value, candidate) for candidate in node["values"]), refs, []
    if op == "TRUE":
        if not isinstance(value, bool):
            return None, refs, [{"code": "FAIL_FACT_BOOLEAN_REQUIRED", "detail": {"fact": fact, "operator": op}}]
        return value is True, refs, []
    if op == "FALSE":
        if not isinstance(value, bool):
            return None, refs, [{"code": "FAIL_FACT_BOOLEAN_REQUIRED", "detail": {"fact": fact, "operator": op}}]
        return value is False, refs, []
    raise ContractPredicateSemanticsInputError(f"predicate_operator_unreachable:{op}")


def evaluate(packet: Mapping[str, Any]) -> dict[str, Any]:
    p = _obj(packet, "packet")
    if p.get("schema_version") != INPUT_SCHEMA_VERSION:
        raise ContractPredicateSemanticsInputError("schema_version_invalid")
    operation_code = _text(p, "operation_code")
    if not operation_code:
        raise ContractPredicateSemanticsInputError("operation_code_missing")
    phase = _text(p, "phase")
    if phase not in SECTIONS_BY_PHASE:
        raise ContractPredicateSemanticsInputError("phase_invalid")

    contracts = [_obj(v, "contract") for v in _arr(p.get("contracts"), "contracts")]
    observations = _obj(p.get("facts"), "facts")
    failures: list[dict[str, Any]] = []
    evaluations: list[dict[str, Any]] = []

    def fail(code: str, detail: Any = None) -> None:
        row: dict[str, Any] = {"code": code}
        if detail is not None:
            row["detail"] = detail
        failures.append(row)

    if not contracts:
        fail("FAIL_RESOLVED_CONTRACTS_EMPTY")

    contract_codes = [_text(c, "contract_code") for c in contracts]
    for code, count in sorted(Counter(contract_codes).items()):
        if not code:
            fail("FAIL_CONTRACT_CODE_MISSING")
        elif count != 1:
            fail("FAIL_RESOLVED_CONTRACT_DUPLICATE", {"contract_code": code, "count": count})

    for contract in contracts:
        code = _text(contract, "contract_code")
        op = _text(contract, "operation_code")
        if op and op != operation_code:
            fail("FAIL_CONTRACT_OPERATION_MISMATCH", {"contract_code": code, "contract_operation_code": op})
        for section in SECTIONS_BY_PHASE[phase]:
            raw_terms = contract.get(section)
            if not isinstance(raw_terms, list):
                fail(
                    "FAIL_TYPED_SECTION_REQUIRED",
                    {"contract_code": code, "section": section, "observed_type": type(raw_terms).__name__},
                )
                continue

            semantic_ids: Counter[str] = Counter()
            for item in raw_terms:
                if isinstance(item, Mapping) and isinstance(item.get("id"), str):
                    semantic_ids[item["id"]] += 1
            for semantic_id, count in sorted(semantic_ids.items()):
                if count != 1:
                    fail(
                        "FAIL_SEMANTIC_TERM_ID_DUPLICATE",
                        {"contract_code": code, "section": section, "id": semantic_id, "count": count},
                    )

            for index, raw_term in enumerate(raw_terms):
                core_term_id = f"{section}[{index}]"
                try:
                    term = _obj(raw_term, "term")
                    _keys_exact(term, {"id", "predicate", "applies_when"}, "term")
                    semantic_id = _term_id(term.get("id"))
                    predicate = _validate_predicate(term.get("predicate"))
                    applies_when = None
                    if "applies_when" in term:
                        applies_when = _validate_predicate(term["applies_when"])
                except ContractPredicateSemanticsInputError as exc:
                    fail(
                        "FAIL_TYPED_TERM_SCHEMA",
                        {"contract_code": code, "section": section, "term_id": core_term_id, "reason": str(exc)},
                    )
                    continue

                term_digest = _sha(term)
                evidence_refs: list[str] = []
                if applies_when is not None:
                    applies, refs, pred_failures = _eval_predicate(applies_when, observations)
                    evidence_refs = _merge_refs([evidence_refs, refs])
                    if pred_failures:
                        for entry in pred_failures:
                            fail(
                                entry["code"],
                                {
                                    **entry.get("detail", {}),
                                    "contract_code": code,
                                    "section": section,
                                    "term_id": core_term_id,
                                    "semantic_id": semantic_id,
                                    "predicate_role": "applies_when",
                                },
                            )
                        continue
                    if applies is False:
                        evaluations.append(
                            {
                                "contract_code": code,
                                "section": section,
                                "term_id": core_term_id,
                                "term_digest": term_digest,
                                "verdict": "NOT_APPLICABLE",
                                "evidence_refs": evidence_refs,
                                "rationale": f"applies_when_false:{semantic_id}",
                            }
                        )
                        continue

                result, refs, pred_failures = _eval_predicate(predicate, observations)
                evidence_refs = _merge_refs([evidence_refs, refs])
                if pred_failures:
                    for entry in pred_failures:
                        fail(
                            entry["code"],
                            {
                                **entry.get("detail", {}),
                                "contract_code": code,
                                "section": section,
                                "term_id": core_term_id,
                                "semantic_id": semantic_id,
                                "predicate_role": "predicate",
                            },
                        )
                    continue
                if not evidence_refs:
                    fail(
                        "FAIL_TERM_EVIDENCE_EMPTY",
                        {
                            "contract_code": code,
                            "section": section,
                            "term_id": core_term_id,
                            "semantic_id": semantic_id,
                        },
                    )
                    continue

                if section == "blocked":
                    verdict = "TRIGGERED" if result else "CLEAR"
                else:
                    verdict = "SATISFIED" if result else "FAILED"
                evaluations.append(
                    {
                        "contract_code": code,
                        "section": section,
                        "term_id": core_term_id,
                        "term_digest": term_digest,
                        "verdict": verdict,
                        "evidence_refs": evidence_refs,
                    }
                )

    return {
        "schema_version": RESULT_SCHEMA_VERSION,
        "verdict": "READY" if not failures else "BLOCK",
        "operation_code": operation_code,
        "phase": phase,
        "counts": {
            "resolved_contracts": len(contracts),
            "evaluations": len(evaluations),
            "failures": len(failures),
        },
        "evaluations": evaluations,
        "failures": failures,
        "packet_sha256": _sha(p),
    }
