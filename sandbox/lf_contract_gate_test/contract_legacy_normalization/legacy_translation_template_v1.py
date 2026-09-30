#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, Mapping

import legacy_contract_normalization_v1 as normalization

CATALOG_SCHEMA_VERSION = "lf-legacy-contract-translation-template-catalog/v1"
SECTIONS = ("required_before_write", "allowed", "blocked", "required_after_write")
DEFAULT_CATALOG_PATH = Path(__file__).with_name("legacy_translation_templates_v1.json")


class LegacyTranslationTemplateError(ValueError):
    pass


def _obj(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise LegacyTranslationTemplateError(f"{label}_must_be_object")
    return value


def _arr(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise LegacyTranslationTemplateError(f"{label}_must_be_array")
    return value


def _sections(contract: Mapping[str, Any]) -> dict[str, Any]:
    missing = [section for section in SECTIONS if section not in contract]
    if missing:
        raise LegacyTranslationTemplateError("source_section_missing:" + ",".join(missing))
    return {section: contract[section] for section in SECTIONS}


def load_catalog(path: Path | None = None) -> dict[str, Any]:
    target = DEFAULT_CATALOG_PATH if path is None else path
    data = json.loads(target.read_text(encoding="utf-8"))
    catalog = dict(_obj(data, "catalog"))
    if catalog.get("schema_version") != CATALOG_SCHEMA_VERSION:
        raise LegacyTranslationTemplateError("catalog_schema_version_invalid")
    templates = [_obj(v, "template") for v in _arr(catalog.get("templates"), "templates")]
    ids = [str(t.get("template_id") or "").strip() for t in templates]
    if any(not v for v in ids):
        raise LegacyTranslationTemplateError("template_id_missing")
    if len(set(ids)) != len(ids):
        raise LegacyTranslationTemplateError("template_id_duplicate")
    return catalog


def exact_template_matches(contract: Mapping[str, Any], catalog: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    source_sections = _sections(contract)
    matches: list[Mapping[str, Any]] = []
    for raw in _arr(catalog.get("templates"), "templates"):
        template = _obj(raw, "template")
        expected = _obj(template.get("source_sections"), "source_sections")
        if normalization._json_equal(source_sections, expected):
            matches.append(template)
    return matches


def select_exact_template(contract: Mapping[str, Any], catalog: Mapping[str, Any]) -> Mapping[str, Any]:
    matches = exact_template_matches(contract, catalog)
    if not matches:
        raise LegacyTranslationTemplateError("exact_template_not_found")
    if len(matches) != 1:
        raise LegacyTranslationTemplateError("exact_template_ambiguous")
    return matches[0]


def instantiate_translation(contract: Mapping[str, Any], template: Mapping[str, Any]) -> dict[str, Any]:
    source_sections = _sections(contract)
    expected = _obj(template.get("source_sections"), "source_sections")
    if not normalization._json_equal(source_sections, expected):
        raise LegacyTranslationTemplateError("template_source_sections_mismatch")

    operation_code = str(contract.get("operation_code") or "").strip()
    contract_code = str(contract.get("contract_code") or "").strip()
    if not operation_code:
        raise LegacyTranslationTemplateError("operation_code_missing")
    if not contract_code:
        raise LegacyTranslationTemplateError("contract_code_missing")

    projection = normalization._source_contract_projection(contract)
    translation = {
        "schema_version": normalization.TRANSLATION_SCHEMA_VERSION,
        "operation_code": operation_code,
        "contract_code": contract_code,
        "source_contract_sha256": normalization._sha(projection),
        "coverage_mode": "FULL",
        "mappings": copy.deepcopy(_arr(template.get("mappings"), "mappings")),
    }
    result = normalization.normalize(
        {
            "schema_version": normalization.INPUT_SCHEMA_VERSION,
            "legacy_contract": copy.deepcopy(dict(contract)),
            "translation": translation,
        }
    )
    if result.get("ready_for_contract_check") is not True:
        raise LegacyTranslationTemplateError("full_translation_not_ready")
    return translation


def instantiate_exact(contract: Mapping[str, Any], catalog: Mapping[str, Any]) -> dict[str, Any]:
    return instantiate_translation(contract, select_exact_template(contract, catalog))
