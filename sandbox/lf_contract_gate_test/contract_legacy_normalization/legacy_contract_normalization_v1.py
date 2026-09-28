#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from collections import Counter
from typing import Any, Mapping

INPUT_SCHEMA_VERSION = "lf-legacy-contract-normalization-input/v1"
RESULT_SCHEMA_VERSION = "lf-legacy-contract-normalization-result/v1"
TRANSLATION_SCHEMA_VERSION = "lf-legacy-contract-translation/v1"
SECTIONS = ("required_before_write", "allowed", "blocked", "required_after_write")
COVERAGE_MODES = frozenset({"FULL", "PARTIAL_SHADOW"})


class LegacyContractNormalizationError(ValueError):
    pass


def _obj(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise LegacyContractNormalizationError(f"{label}_must_be_object")
    return value


def _arr(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise LegacyContractNormalizationError(f"{label}_must_be_array")
    return value


def _text(row: Mapping[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else ""


def _canon(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise LegacyContractNormalizationError("non_json_value") from exc


def _sha(value: Any) -> str:
    return hashlib.sha256(_canon(value).encode("utf-8")).hexdigest()


def _json_equal(left: Any, right: Any) -> bool:
    return _canon(left) == _canon(right)


def _decode_pointer_token(token: str) -> str:
    return token.replace("~1", "/").replace("~0", "~")


def _pointer_get(root: Any, pointer: str) -> Any:
    if pointer == "":
        return root
    if not isinstance(pointer, str) or not pointer.startswith("/"):
        raise LegacyContractNormalizationError("source_pointer_invalid")
    current = root
    for raw in pointer.split("/")[1:]:
        token = _decode_pointer_token(raw)
        if isinstance(current, Mapping):
            if token not in current:
                raise LegacyContractNormalizationError(f"source_pointer_missing:{pointer}")
            current = current[token]
        elif isinstance(current, list):
            if not token.isdigit():
                raise LegacyContractNormalizationError(f"source_pointer_index_invalid:{pointer}")
            index = int(token)
            if index >= len(current):
                raise LegacyContractNormalizationError(f"source_pointer_missing:{pointer}")
            current = current[index]
        else:
            raise LegacyContractNormalizationError(f"source_pointer_traverses_scalar:{pointer}")
    return current


def _escape_pointer_token(token: str) -> str:
    return token.replace("~", "~0").replace("/", "~1")


def _source_atoms(value: Any, pointer: str) -> list[str]:
    if isinstance(value, Mapping):
        out: list[str] = []
        for key in sorted(value):
            child = f"{pointer}/{_escape_pointer_token(str(key))}"
            out.extend(_source_atoms(value[key], child))
        return out
    if isinstance(value, list):
        out: list[str] = []
        for index, item in enumerate(value):
            out.extend(_source_atoms(item, f"{pointer}/{index}"))
        return out
    return [pointer]


def _legacy_atoms(contract: Mapping[str, Any]) -> list[str]:
    atoms: list[str] = []
    for section in SECTIONS:
        if section not in contract:
            raise LegacyContractNormalizationError(f"legacy_section_missing:{section}")
        atoms.extend(_source_atoms(contract[section], f"/{section}"))
    return sorted(atoms)


def _validate_typed_term(term: Mapping[str, Any]) -> None:
    allowed = {"id", "predicate", "applies_when"}
    extra = sorted(set(term) - allowed)
    if extra:
        raise LegacyContractNormalizationError(f"typed_term_unexpected_keys:{','.join(extra)}")
    if not _text(term, "id"):
        raise LegacyContractNormalizationError("typed_term_id_missing")
    if not isinstance(term.get("predicate"), Mapping):
        raise LegacyContractNormalizationError("typed_term_predicate_missing")
    if "applies_when" in term and not isinstance(term.get("applies_when"), Mapping):
        raise LegacyContractNormalizationError("typed_term_applies_when_invalid")


def normalize(packet: Mapping[str, Any]) -> dict[str, Any]:
    p = _obj(packet, "packet")
    if p.get("schema_version") != INPUT_SCHEMA_VERSION:
        raise LegacyContractNormalizationError("schema_version_invalid")

    contract = _obj(p.get("legacy_contract"), "legacy_contract")
    translation = _obj(p.get("translation"), "translation")
    if translation.get("schema_version") != TRANSLATION_SCHEMA_VERSION:
        raise LegacyContractNormalizationError("translation_schema_version_invalid")

    operation_code = _text(contract, "operation_code")
    contract_code = _text(contract, "contract_code")
    if not operation_code:
        raise LegacyContractNormalizationError("operation_code_missing")
    if not contract_code:
        raise LegacyContractNormalizationError("contract_code_missing")
    if _text(translation, "operation_code") != operation_code:
        raise LegacyContractNormalizationError("translation_operation_mismatch")
    if _text(translation, "contract_code") != contract_code:
        raise LegacyContractNormalizationError("translation_contract_mismatch")

    expected_source_sha = _text(translation, "source_contract_sha256")
    source_sha = _sha(contract)
    if expected_source_sha != source_sha:
        raise LegacyContractNormalizationError("source_contract_sha256_mismatch")

    coverage_mode = _text(translation, "coverage_mode")
    if coverage_mode not in COVERAGE_MODES:
        raise LegacyContractNormalizationError("coverage_mode_invalid")

    mappings = [_obj(v, "mapping") for v in _arr(translation.get("mappings"), "mappings")]
    source_atoms = _legacy_atoms(contract)
    source_atom_set = set(source_atoms)
    covered: list[str] = []
    terms_by_section: dict[str, list[dict[str, Any]]] = {section: [] for section in SECTIONS}
    semantic_ids: Counter[tuple[str, str]] = Counter()

    for mapping in mappings:
        section = _text(mapping, "section")
        if section not in SECTIONS:
            raise LegacyContractNormalizationError(f"mapping_section_invalid:{section or '<missing>'}")
        pointer = _text(mapping, "source_pointer")
        if pointer not in source_atom_set:
            raise LegacyContractNormalizationError(f"mapping_source_pointer_not_atom:{pointer or '<missing>'}")
        if not pointer.startswith(f"/{section}/") and pointer != f"/{section}":
            raise LegacyContractNormalizationError("mapping_section_pointer_mismatch")
        if "expected_source" not in mapping:
            raise LegacyContractNormalizationError("mapping_expected_source_missing")
        observed = _pointer_get(contract, pointer)
        if not _json_equal(observed, mapping["expected_source"]):
            raise LegacyContractNormalizationError(f"mapping_source_value_mismatch:{pointer}")
        term = dict(_obj(mapping.get("typed_term"), "typed_term"))
        _validate_typed_term(term)
        semantic_ids[(section, _text(term, "id"))] += 1
        covered.append(pointer)
        terms_by_section[section].append(term)

    duplicates = sorted(pointer for pointer, count in Counter(covered).items() if count != 1)
    if duplicates:
        raise LegacyContractNormalizationError(f"duplicate_source_mapping:{','.join(duplicates)}")
    duplicate_ids = sorted(f"{section}:{term_id}" for (section, term_id), count in semantic_ids.items() if count != 1)
    if duplicate_ids:
        raise LegacyContractNormalizationError(f"duplicate_typed_term_id:{','.join(duplicate_ids)}")

    covered_set = set(covered)
    missing_atoms = sorted(source_atom_set - covered_set)
    unexpected_coverage = sorted(covered_set - source_atom_set)
    if unexpected_coverage:
        raise LegacyContractNormalizationError("unexpected_coverage")
    if coverage_mode == "FULL" and missing_atoms:
        raise LegacyContractNormalizationError("full_coverage_incomplete:" + ",".join(missing_atoms))

    candidate_contract: dict[str, Any] = {
        "operation_code": operation_code,
        "contract_code": contract_code,
        **terms_by_section,
    }
    ready = coverage_mode == "FULL" and not missing_atoms
    return {
        "schema_version": RESULT_SCHEMA_VERSION,
        "status": "READY" if ready else "PARTIAL_SHADOW",
        "ready_for_contract_check": ready,
        "operation_code": operation_code,
        "contract_code": contract_code,
        "source_contract_sha256": source_sha,
        "translation_sha256": _sha(translation),
        "coverage": {
            "mode": coverage_mode,
            "source_atoms": len(source_atoms),
            "covered_atoms": len(covered_set),
            "missing_atoms": missing_atoms,
        },
        "candidate_contract": candidate_contract,
        "normalized_contract": candidate_contract if ready else None,
        "packet_sha256": _sha(p),
    }
