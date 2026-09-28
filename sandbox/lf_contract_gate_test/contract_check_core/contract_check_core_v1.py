#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from typing import Any, Mapping

SCHEMA_VERSION = "lf-contract-check-input/v1"
RESULT_SCHEMA_VERSION = "lf-contract-check-result/v1"
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
SECTIONS_BY_PHASE = {
    "ENTRY": ("required_before_write", "allowed", "blocked"),
    "CLOSURE": ("required_before_write", "allowed", "blocked", "required_after_write"),
}
PASS_VERDICTS = {
    "required_before_write": frozenset({"SATISFIED", "NOT_APPLICABLE"}),
    "allowed": frozenset({"SATISFIED", "NOT_APPLICABLE"}),
    "blocked": frozenset({"CLEAR", "NOT_APPLICABLE"}),
    "required_after_write": frozenset({"SATISFIED", "NOT_APPLICABLE"}),
}
ALL_VERDICTS = {
    "required_before_write": frozenset({"SATISFIED", "FAILED", "NOT_APPLICABLE"}),
    "allowed": frozenset({"SATISFIED", "FAILED", "NOT_APPLICABLE"}),
    "blocked": frozenset({"CLEAR", "TRIGGERED", "NOT_APPLICABLE"}),
    "required_after_write": frozenset({"SATISFIED", "FAILED", "NOT_APPLICABLE"}),
}


class ContractCheckInputError(ValueError):
    pass


def _obj(v: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(v, Mapping):
        raise ContractCheckInputError(f"{label}_must_be_object")
    return v


def _arr(v: Any, label: str) -> list[Any]:
    if not isinstance(v, list):
        raise ContractCheckInputError(f"{label}_must_be_array")
    return v


def _text(row: Mapping[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else ""


def _canon(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha(value: Any) -> str:
    return hashlib.sha256(_canon(value).encode("utf-8")).hexdigest()


def _terms(section: str, value: Any) -> list[dict[str, str]]:
    if isinstance(value, list):
        return [{"term_id": f"{section}[{i}]", "term_digest": _sha(item)} for i, item in enumerate(value)]
    if isinstance(value, Mapping):
        return [{"term_id": f"{section}.{key}", "term_digest": _sha(value[key])} for key in sorted(value)]
    if value is None:
        return []
    return [{"term_id": section, "term_digest": _sha(value)}]


def evaluate(packet: Mapping[str, Any]) -> dict[str, Any]:
    p = _obj(packet, "packet")
    if p.get("schema_version") != SCHEMA_VERSION:
        raise ContractCheckInputError("schema_version_invalid")
    operation_code = _text(p, "operation_code")
    if not operation_code:
        raise ContractCheckInputError("operation_code_missing")
    phase = _text(p, "phase")
    if phase not in SECTIONS_BY_PHASE:
        raise ContractCheckInputError("phase_invalid")

    contracts = [_obj(v, "contract") for v in _arr(p.get("contracts"), "contracts")]
    evaluations = [_obj(v, "evaluation") for v in _arr(p.get("evaluations"), "evaluations")]
    failures: list[dict[str, Any]] = []

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

    expected: dict[tuple[str, str, str], str] = {}
    for contract in contracts:
        code = _text(contract, "contract_code")
        op = _text(contract, "operation_code")
        if op and op != operation_code:
            fail("FAIL_CONTRACT_OPERATION_MISMATCH", {"contract_code": code, "contract_operation_code": op})
        sha = _text(contract, "contract_sha")
        if SHA64_RE.fullmatch(sha) is None:
            fail("FAIL_CONTRACT_SHA_INVALID", code or None)
        for section in SECTIONS_BY_PHASE[phase]:
            for term in _terms(section, contract.get(section)):
                key = (code, section, term["term_id"])
                if key in expected:
                    fail("FAIL_TERM_ID_COLLISION", {"contract_code": code, "section": section, "term_id": term["term_id"]})
                expected[key] = term["term_digest"]

    seen: Counter[tuple[str, str, str]] = Counter()
    for ev in evaluations:
        code = _text(ev, "contract_code")
        section = _text(ev, "section")
        term_id = _text(ev, "term_id")
        verdict = _text(ev, "verdict")
        digest = _text(ev, "term_digest")
        key = (code, section, term_id)
        seen[key] += 1
        if key not in expected:
            fail("FAIL_UNDECLARED_TERM_EVALUATION", {"contract_code": code, "section": section, "term_id": term_id})
            continue
        if digest != expected[key]:
            fail("FAIL_TERM_DIGEST_MISMATCH", {"contract_code": code, "section": section, "term_id": term_id})
        if verdict not in ALL_VERDICTS[section]:
            fail("FAIL_TERM_VERDICT_INVALID", {"contract_code": code, "section": section, "term_id": term_id, "verdict": verdict})
        evidence_refs = ev.get("evidence_refs")
        if not isinstance(evidence_refs, list) or not evidence_refs or any(not isinstance(v, str) or not v.strip() for v in evidence_refs):
            fail("FAIL_TERM_EVIDENCE_MISSING", {"contract_code": code, "section": section, "term_id": term_id})
        if verdict == "NOT_APPLICABLE" and not _text(ev, "rationale"):
            fail("FAIL_NOT_APPLICABLE_RATIONALE_MISSING", {"contract_code": code, "section": section, "term_id": term_id})
        if verdict in ALL_VERDICTS[section] and verdict not in PASS_VERDICTS[section]:
            fail("FAIL_CONTRACT_TERM_NOT_SATISFIED", {"contract_code": code, "section": section, "term_id": term_id, "verdict": verdict})

    for key, digest in sorted(expected.items()):
        count = seen.get(key, 0)
        if count == 0:
            code, section, term_id = key
            fail("FAIL_CONTRACT_TERM_UNEVALUATED", {"contract_code": code, "section": section, "term_id": term_id, "term_digest": digest})
        elif count != 1:
            code, section, term_id = key
            fail("FAIL_TERM_EVALUATION_DUPLICATE", {"contract_code": code, "section": section, "term_id": term_id, "count": count})

    verdict = "PASS" if not failures else "BLOCK"
    return {
        "schema_version": RESULT_SCHEMA_VERSION,
        "verdict": verdict,
        "operation_code": operation_code,
        "phase": phase,
        "counts": {
            "resolved_contracts": len(contracts),
            "declared_terms": len(expected),
            "evaluations": len(evaluations),
            "failures": len(failures),
        },
        "failures": failures,
        "packet_sha256": _sha(p),
    }
