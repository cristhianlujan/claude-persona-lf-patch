from __future__ import annotations

import copy
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_predicate_semantics"))
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/contract_check_core"))

import legacy_contract_normalization_v1 as normalization
import legacy_translation_template_v1 as templates
import contract_predicate_semantics_v1 as semantics
import contract_check_core_v1 as core
import contract_check_batch_test_support_v1 as batch_support

CATALOG_PATH = HERE / "legacy_translation_templates_batch2_v1.json"
EXPECTED_IDS = {
    "ADAPTER_DEPTH_V1",
    "ADAPTER_EXAMPLES_DEPTH_V1",
    "CARD_EXAMPLES_DEPTH_V1",
    "PROFILE_GENERAL_DEPTH_V1",
    "SKILL_GENERAL_DEPTH_V1",
    "CARD_NO_CLOSE_V1",
    "SKILL_NO_CLOSE_V1",
    "DS_BUILD_NO_CLOSE_V1",
    "PROFILE_NO_CLOSE_V1",
}


def source_row(template: dict[str, Any], index: int) -> dict[str, Any]:
    return {
        "operation_code": f"TEST_OPERATION_{index}",
        "contract_code": f"TEST_CONTRACT_{index}",
        "contract_path": f"supabase://test/{index}",
        "contract_sha": None,
        **copy.deepcopy(template["source_sections"]),
        "status": "ACTIVE_ENFORCEMENT",
        "created_at": "ignored-transport-metadata",
    }


def set_observation(obs: dict[str, Any], fact: str, present: bool, value: Any = None) -> None:
    row: dict[str, Any] = {"present": present, "evidence_refs": [f"evidence:{fact}"]}
    if present:
        row["value"] = value
    existing = obs.get(fact)
    if existing is not None and existing != row:
        raise AssertionError(f"conflicting fact requirement: {fact}: {existing} vs {row}")
    obs[fact] = row


def satisfy(predicate: dict[str, Any], desired: bool, obs: dict[str, Any]) -> None:
    op = predicate["op"]
    if op == "TRUE":
        set_observation(obs, predicate["fact"], True, desired)
    elif op == "FALSE":
        set_observation(obs, predicate["fact"], True, not desired)
    elif op == "EQ":
        if desired:
            set_observation(obs, predicate["fact"], True, copy.deepcopy(predicate["value"]))
        else:
            set_observation(obs, predicate["fact"], True, {"not": copy.deepcopy(predicate["value"])})
    elif op == "NEQ":
        if desired:
            set_observation(obs, predicate["fact"], True, {"different": True})
        else:
            set_observation(obs, predicate["fact"], True, copy.deepcopy(predicate["value"]))
    elif op == "IN":
        values = predicate["values"]
        if desired:
            set_observation(obs, predicate["fact"], True, copy.deepcopy(values[0]))
        else:
            set_observation(obs, predicate["fact"], True, "__NOT_IN__")
    elif op == "NOT_IN":
        values = predicate["values"]
        if desired:
            set_observation(obs, predicate["fact"], True, "__NOT_IN__")
        else:
            set_observation(obs, predicate["fact"], True, copy.deepcopy(values[0]))
    elif op == "EXISTS":
        if desired:
            set_observation(obs, predicate["fact"], True, True)
        else:
            set_observation(obs, predicate["fact"], False)
    elif op == "ABSENT":
        if desired:
            set_observation(obs, predicate["fact"], False)
        else:
            set_observation(obs, predicate["fact"], True, True)
    elif op == "ALL":
        if desired:
            for arg in predicate["args"]:
                satisfy(arg, True, obs)
        else:
            satisfy(predicate["args"][0], False, obs)
            for arg in predicate["args"][1:]:
                satisfy(arg, True, obs)
    elif op == "ANY":
        if desired:
            satisfy(predicate["args"][0], True, obs)
            for arg in predicate["args"][1:]:
                satisfy(arg, False, obs)
        else:
            for arg in predicate["args"]:
                satisfy(arg, False, obs)
    elif op == "NOT":
        satisfy(predicate["arg"], not desired, obs)
    else:
        raise AssertionError(f"unsupported test predicate: {op}")


def facts_for_typed_contract(contract: dict[str, Any]) -> dict[str, Any]:
    obs: dict[str, Any] = {}
    for section in ("required_before_write", "allowed", "blocked", "required_after_write"):
        desired = section != "blocked"
        for term in contract[section]:
            applies = term.get("applies_when")
            if applies is not None:
                satisfy(applies, True, obs)
            satisfy(term["predicate"], desired, obs)
    return obs


def main() -> None:
    catalog = templates.load_catalog(CATALOG_PATH)
    ids = {row["template_id"] for row in catalog["templates"]}
    assert ids == EXPECTED_IDS
    assert catalog["coverage"]["cumulative_contracts_covered"] == 20
    assert catalog["coverage"]["cumulative_semantic_definitions_covered"] == 12

    checks = 0
    for index, template in enumerate(catalog["templates"], start=1):
        source = source_row(template, index)
        assert templates.select_exact_template(source, catalog)["template_id"] == template["template_id"]
        translation = templates.instantiate_translation(source, template)
        result = normalization.normalize(
            {
                "schema_version": normalization.INPUT_SCHEMA_VERSION,
                "legacy_contract": source,
                "translation": translation,
            }
        )
        assert result["ready_for_contract_check"] is True
        typed = result["normalized_contract"]
        facts = facts_for_typed_contract(typed)
        semantic_result = semantics.evaluate(
            {
                "schema_version": semantics.INPUT_SCHEMA_VERSION,
                "operation_code": source["operation_code"],
                "phase": "CLOSURE",
                "contracts": [typed],
                "facts": facts,
            }
        )
        assert semantic_result["verdict"] == "READY", semantic_result
        assert all(e["verdict"] in {"SATISFIED", "CLEAR", "NOT_APPLICABLE"} for e in semantic_result["evaluations"])
        core_result = batch_support.evaluate_core(
            core,
            source["operation_code"],
            typed,
            semantic_result["evaluations"],
        )
        assert core_result["verdict"] == "PASS", core_result
        checks += 1

    drift = source_row(catalog["templates"][0], 99)
    drift["allowed"]["status"] = "MUTATED"
    try:
        templates.select_exact_template(drift, catalog)
    except templates.LegacyTranslationTemplateError as exc:
        assert str(exc) == "exact_template_not_found"
    else:
        raise AssertionError("semantic drift must not exact-match")
    checks += 1

    assert checks == 10
    print("PASS_LEGACY_TRANSLATION_TEMPLATES_BATCH2_V1=10/10")


if __name__ == "__main__":
    main()
