#!/usr/bin/env python3
"""Pure semantic integration for the single Contract Check capability.

Consumes the exact Contract Resolution result, explicit contract-mode bindings,
facts/evidence, and composes already-existing normalization, predicate semantics,
and Contract Check Core. It does not resolve contracts, decide applicability, or
accept upstream term verdicts.
"""
from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_legacy_normalization"))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_predicate_semantics"))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_check_core"))

import legacy_contract_normalization_v1 as normalization
import contract_predicate_semantics_v1 as semantics
import contract_check_core_v1 as core

INPUT_SCHEMA_VERSION = "lf-contract-check-semantic-integration-input/v1"
RESULT_SCHEMA_VERSION = "lf-contract-check-semantic-integration-result/v1"
RESOLUTION_SCHEMA_VERSION = "lf-contract-resolution-result/v1"
RESOLUTION_BASIS = "ALL_ACTIVE_CONTRACTS_FOR_OPERATION"
SECTIONS = ("required_before_write", "allowed", "blocked", "required_after_write")
SOURCE_MODES = frozenset({"TYPED", "LEGACY_TRANSLATION"})


class ContractCheckSemanticIntegrationInputError(ValueError):
    pass


def _obj(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ContractCheckSemanticIntegrationInputError(f"{label}_must_be_object")
    return value


def _arr(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ContractCheckSemanticIntegrationInputError(f"{label}_must_be_array")
    return value


def _text(row: Mapping[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else ""


def _canon(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise ContractCheckSemanticIntegrationInputError("non_json_value") from exc


def _sha(value: Any) -> str:
    return hashlib.sha256(_canon(value).encode("utf-8")).hexdigest()


def _fail(stage: str, code: str, detail: Any = None) -> dict[str, Any]:
    row: dict[str, Any] = {"stage": stage, "code": code}
    if detail is not None:
        row["detail"] = detail
    return row


def _result(
    *,
    packet: Mapping[str, Any],
    verdict: str,
    stage: str,
    operation_code: str,
    phase: str,
    resolution_sha256: str,
    failures: list[dict[str, Any]],
    typed_contracts: list[dict[str, Any]] | None = None,
    semantic_result: dict[str, Any] | None = None,
    core_result: dict[str, Any] | None = None,
    mode_counts: Mapping[str, int] | None = None,
) -> dict[str, Any]:
    typed_contracts = typed_contracts or []
    semantic_evaluations = 0 if semantic_result is None else int(semantic_result.get("counts", {}).get("evaluations", 0))
    return {
        "schema_version": RESULT_SCHEMA_VERSION,
        "verdict": verdict,
        "stage": stage,
        "operation_code": operation_code,
        "phase": phase,
        "resolution_sha256": resolution_sha256,
        "counts": {
            "resolved_contracts": len(typed_contracts),
            "typed_direct": int((mode_counts or {}).get("TYPED", 0)),
            "normalized_legacy": int((mode_counts or {}).get("LEGACY_TRANSLATION", 0)),
            "semantic_evaluations": semantic_evaluations,
            "failures": len(failures),
        },
        "failures": failures,
        "semantic_result": semantic_result,
        "core_result": core_result,
        "packet_sha256": _sha(packet),
    }


def _validate_resolution(resolution: Mapping[str, Any]) -> tuple[str, list[Mapping[str, Any]], str, list[dict[str, Any]]]:
    failures: list[dict[str, Any]] = []
    if resolution.get("schema_version") != RESOLUTION_SCHEMA_VERSION:
        failures.append(_fail("RESOLUTION", "FAIL_RESOLUTION_SCHEMA"))
    operation_code = _text(resolution, "operation_code")
    if not operation_code:
        failures.append(_fail("RESOLUTION", "FAIL_RESOLUTION_OPERATION_CODE"))
    if resolution.get("resolution_basis") != RESOLUTION_BASIS:
        failures.append(_fail("RESOLUTION", "FAIL_RESOLUTION_BASIS"))
    rows_raw = resolution.get("resolved_contracts")
    if not isinstance(rows_raw, list):
        failures.append(_fail("RESOLUTION", "FAIL_RESOLVED_CONTRACTS_SHAPE"))
        rows: list[Mapping[str, Any]] = []
    else:
        rows = []
        for index, raw in enumerate(rows_raw):
            if not isinstance(raw, Mapping):
                failures.append(_fail("RESOLUTION", "FAIL_RESOLVED_CONTRACT_SHAPE", {"index": index}))
            else:
                rows.append(raw)
    count = resolution.get("contract_count")
    if not isinstance(count, int) or isinstance(count, bool) or count != len(rows):
        failures.append(_fail("RESOLUTION", "FAIL_RESOLUTION_CONTRACT_COUNT", {"declared": count, "observed": len(rows)}))
    if not rows:
        failures.append(_fail("RESOLUTION", "FAIL_RESOLVED_CONTRACTS_EMPTY"))

    codes: list[str] = []
    for index, row in enumerate(rows):
        code = _text(row, "contract_code")
        codes.append(code)
        if not code:
            failures.append(_fail("RESOLUTION", "FAIL_RESOLVED_CONTRACT_CODE", {"index": index}))
        row_op = _text(row, "operation_code")
        if row_op != operation_code:
            failures.append(_fail("RESOLUTION", "FAIL_RESOLUTION_CONTRACT_OPERATION_MISMATCH", {"contract_code": code, "contract_operation_code": row_op}))
    for code, duplicate_count in sorted(Counter(codes).items()):
        if code and duplicate_count != 1:
            failures.append(_fail("RESOLUTION", "FAIL_RESOLVED_CONTRACT_DUPLICATE", {"contract_code": code, "count": duplicate_count}))

    declared_sha = _text(resolution, "resolution_sha256")
    unsigned = dict(resolution)
    unsigned.pop("resolution_sha256", None)
    expected_sha = _sha(unsigned)
    if declared_sha != expected_sha:
        failures.append(_fail("RESOLUTION", "FAIL_RESOLUTION_SHA256_MISMATCH"))
    return operation_code, rows, declared_sha, failures


def _validate_bindings(bindings_raw: Any, contract_codes: set[str]) -> tuple[dict[str, Mapping[str, Any]], Counter[str], list[dict[str, Any]]]:
    failures: list[dict[str, Any]] = []
    bindings: dict[str, Mapping[str, Any]] = {}
    modes: Counter[str] = Counter()
    seen: Counter[str] = Counter()

    try:
        raw_list = _arr(bindings_raw, "bindings")
    except ContractCheckSemanticIntegrationInputError as exc:
        return {}, modes, [_fail("BINDINGS", "FAIL_BINDINGS_SHAPE", str(exc))]

    for index, raw in enumerate(raw_list):
        if not isinstance(raw, Mapping):
            failures.append(_fail("BINDINGS", "FAIL_BINDING_SHAPE", {"index": index}))
            continue
        code = _text(raw, "contract_code")
        mode = _text(raw, "source_mode")
        seen[code] += 1
        if not code:
            failures.append(_fail("BINDINGS", "FAIL_BINDING_CONTRACT_CODE", {"index": index}))
            continue
        if mode not in SOURCE_MODES:
            failures.append(_fail("BINDINGS", "FAIL_BINDING_SOURCE_MODE", {"contract_code": code, "source_mode": mode}))
            continue
        allowed_keys = {"contract_code", "source_mode"} if mode == "TYPED" else {"contract_code", "source_mode", "translation"}
        extra = sorted(set(raw) - allowed_keys)
        if extra:
            failures.append(_fail("BINDINGS", "FAIL_BINDING_UNEXPECTED_KEYS", {"contract_code": code, "keys": extra}))
        if mode == "TYPED" and "translation" in raw:
            failures.append(_fail("BINDINGS", "FAIL_TYPED_BINDING_TRANSLATION_FORBIDDEN", {"contract_code": code}))
        if mode == "LEGACY_TRANSLATION" and not isinstance(raw.get("translation"), Mapping):
            failures.append(_fail("BINDINGS", "FAIL_LEGACY_BINDING_TRANSLATION_REQUIRED", {"contract_code": code}))
        modes[mode] += 1
        if code not in bindings:
            bindings[code] = raw

    for code, duplicate_count in sorted(seen.items()):
        if code and duplicate_count != 1:
            failures.append(_fail("BINDINGS", "FAIL_BINDING_DUPLICATE", {"contract_code": code, "count": duplicate_count}))

    binding_codes = {code for code in bindings if code}
    missing = sorted(contract_codes - binding_codes)
    extra_codes = sorted(binding_codes - contract_codes)
    if missing:
        failures.append(_fail("BINDINGS", "FAIL_BINDING_MISSING", {"contract_codes": missing}))
    if extra_codes:
        failures.append(_fail("BINDINGS", "FAIL_BINDING_UNDECLARED", {"contract_codes": extra_codes}))
    return bindings, modes, failures


def _typed_projection(contract: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "operation_code": _text(contract, "operation_code"),
        "contract_code": _text(contract, "contract_code"),
        **{section: contract.get(section) for section in SECTIONS},
    }


def evaluate(packet: Mapping[str, Any]) -> dict[str, Any]:
    p = _obj(packet, "packet")
    allowed_top = {"schema_version", "phase", "resolution", "bindings", "facts"}
    extra_top = sorted(set(p) - allowed_top)
    if extra_top:
        raise ContractCheckSemanticIntegrationInputError("unexpected_top_level_keys:" + ",".join(extra_top))
    if p.get("schema_version") != INPUT_SCHEMA_VERSION:
        raise ContractCheckSemanticIntegrationInputError("schema_version_invalid")
    phase = _text(p, "phase")
    if phase not in core.SECTIONS_BY_PHASE:
        raise ContractCheckSemanticIntegrationInputError("phase_invalid")
    resolution = _obj(p.get("resolution"), "resolution")
    facts = _obj(p.get("facts"), "facts")

    operation_code, resolved_contracts, resolution_sha256, resolution_failures = _validate_resolution(resolution)
    if resolution_failures:
        return _result(
            packet=p,
            verdict="BLOCK",
            stage="RESOLUTION",
            operation_code=operation_code,
            phase=phase,
            resolution_sha256=resolution_sha256,
            failures=resolution_failures,
        )

    contract_codes = {_text(row, "contract_code") for row in resolved_contracts}
    bindings, mode_counts, binding_failures = _validate_bindings(p.get("bindings"), contract_codes)
    if binding_failures:
        return _result(
            packet=p,
            verdict="BLOCK",
            stage="BINDINGS",
            operation_code=operation_code,
            phase=phase,
            resolution_sha256=resolution_sha256,
            failures=binding_failures,
            mode_counts=mode_counts,
        )

    typed_contracts: list[dict[str, Any]] = []
    normalization_failures: list[dict[str, Any]] = []
    for contract in resolved_contracts:
        code = _text(contract, "contract_code")
        binding = bindings[code]
        mode = _text(binding, "source_mode")
        if mode == "TYPED":
            typed_contracts.append(_typed_projection(contract))
            continue
        try:
            normalized = normalization.normalize(
                {
                    "schema_version": normalization.INPUT_SCHEMA_VERSION,
                    "legacy_contract": dict(contract),
                    "translation": dict(binding["translation"]),
                }
            )
        except normalization.LegacyContractNormalizationError as exc:
            normalization_failures.append(_fail("NORMALIZATION", "FAIL_LEGACY_NORMALIZATION", {"contract_code": code, "reason": str(exc)}))
            continue
        if normalized.get("ready_for_contract_check") is not True or not isinstance(normalized.get("normalized_contract"), Mapping):
            normalization_failures.append(_fail("NORMALIZATION", "FAIL_LEGACY_NORMALIZATION_NOT_READY", {"contract_code": code, "status": normalized.get("status")}))
            continue
        typed_contracts.append(dict(normalized["normalized_contract"]))

    typed_contracts.sort(key=lambda row: row["contract_code"])
    if normalization_failures:
        return _result(
            packet=p,
            verdict="BLOCK",
            stage="NORMALIZATION",
            operation_code=operation_code,
            phase=phase,
            resolution_sha256=resolution_sha256,
            failures=normalization_failures,
            typed_contracts=typed_contracts,
            mode_counts=mode_counts,
        )

    try:
        semantic_result = semantics.evaluate(
            {
                "schema_version": semantics.INPUT_SCHEMA_VERSION,
                "operation_code": operation_code,
                "phase": phase,
                "contracts": typed_contracts,
                "facts": facts,
            }
        )
    except semantics.ContractPredicateSemanticsInputError as exc:
        return _result(
            packet=p,
            verdict="BLOCK",
            stage="PREDICATE_SEMANTICS",
            operation_code=operation_code,
            phase=phase,
            resolution_sha256=resolution_sha256,
            failures=[_fail("PREDICATE_SEMANTICS", "FAIL_PREDICATE_SEMANTICS_INPUT", str(exc))],
            typed_contracts=typed_contracts,
            mode_counts=mode_counts,
        )

    if semantic_result.get("verdict") != "READY":
        failures = [_fail("PREDICATE_SEMANTICS", entry.get("code", "FAIL_PREDICATE_SEMANTICS"), entry.get("detail")) for entry in semantic_result.get("failures", [])]
        if not failures:
            failures = [_fail("PREDICATE_SEMANTICS", "FAIL_PREDICATE_SEMANTICS_NOT_READY")]
        return _result(
            packet=p,
            verdict="BLOCK",
            stage="PREDICATE_SEMANTICS",
            operation_code=operation_code,
            phase=phase,
            resolution_sha256=resolution_sha256,
            failures=failures,
            typed_contracts=typed_contracts,
            semantic_result=semantic_result,
            mode_counts=mode_counts,
        )

    try:
        core_result = core.evaluate(
            {
                "schema_version": core.SCHEMA_VERSION,
                "operation_code": operation_code,
                "phase": phase,
                "contracts": typed_contracts,
                "evaluations": semantic_result["evaluations"],
            }
        )
    except core.ContractCheckInputError as exc:
        return _result(
            packet=p,
            verdict="BLOCK",
            stage="CONTRACT_CHECK_CORE",
            operation_code=operation_code,
            phase=phase,
            resolution_sha256=resolution_sha256,
            failures=[_fail("CONTRACT_CHECK_CORE", "FAIL_CONTRACT_CHECK_CORE_INPUT", str(exc))],
            typed_contracts=typed_contracts,
            semantic_result=semantic_result,
            mode_counts=mode_counts,
        )

    core_failures = [_fail("CONTRACT_CHECK_CORE", entry.get("code", "FAIL_CONTRACT_CHECK_CORE"), entry.get("detail")) for entry in core_result.get("failures", [])]
    verdict = "PASS" if core_result.get("verdict") == "PASS" else "BLOCK"
    return _result(
        packet=p,
        verdict=verdict,
        stage="COMPLETE" if verdict == "PASS" else "CONTRACT_CHECK_CORE",
        operation_code=operation_code,
        phase=phase,
        resolution_sha256=resolution_sha256,
        failures=core_failures,
        typed_contracts=typed_contracts,
        semantic_result=semantic_result,
        core_result=core_result,
        mode_counts=mode_counts,
    )
