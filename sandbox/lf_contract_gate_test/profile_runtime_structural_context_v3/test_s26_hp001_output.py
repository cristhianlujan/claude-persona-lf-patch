#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
FIXTURE = HERE / "s26_hp001"
OUTPUT = FIXTURE / "manual_profile_output.json"
RECEIPT = FIXTURE / "manual_profile_execution_receipt.json"
INPUT = FIXTURE / "input.txt"
UI_VALIDATOR = REPO / "profiles/ui_architect/validators/validate_ui_architect_output.py"
BOUNDARY_VALIDATOR = REPO / "profiles/ui_architect/validators/validate_composer_payload_boundary.py"


def load_json(path: Path):
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"NOT_OBJECT:{path}")
    return value


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def component_map(data: dict) -> dict[str, dict]:
    tree = data.get("deliverable_created", {}).get("component_tree", [])
    return {str(item.get("component_id")): item for item in tree if isinstance(item, dict) and item.get("component_id")}


def material_errors(data: dict) -> list[str]:
    errors: list[str] = []
    deliverable = data.get("deliverable_created") or {}
    screen = deliverable.get("screen_definition") or {}
    if screen.get("task_mode") != "CREATE_NEW":
        errors.append("TASK_MODE_NOT_CREATE_NEW")
    expected_sections = {"header_search", "category_navigation", "featured_services", "service_cards"}
    if not expected_sections.issubset(set(screen.get("required_sections") or [])):
        errors.append("REQUIRED_SECTIONS_MISSING")
    if set(screen.get("design_intent") or []) != {"clear", "professional", "easy_to_navigate"}:
        errors.append("DESIGN_INTENT_INCOMPLETE")
    if screen.get("implementation_readiness") != "STRUCTURED_SPEC_READY_FOR_NEXT_AGENT":
        errors.append("IMPLEMENTATION_HANDOFF_NOT_READY")

    components = component_map(data)
    required_components = {
        "header_search", "category_navigation", "featured_services", "service_cards",
        "service_card_template", "service_title", "service_provider", "service_price", "service_cta"
    }
    missing = sorted(required_components - set(components))
    if missing:
        errors.append("MATERIAL_COMPONENTS_MISSING:" + ",".join(missing))
    template = components.get("service_card_template") or {}
    fields = (template.get("content") or {}).get("fields") if isinstance(template.get("content"), dict) else None
    if set(fields or []) != {"title", "provider", "price", "call_to_action"}:
        errors.append("SERVICE_CARD_FIELDS_INCOMPLETE")
    if "remediation_actions" in deliverable:
        errors.append("CREATE_NEW_REMEDIATION_FORBIDDEN")
    if data.get("handoff_to_next", {}).get("payload_ref") != "composer_payload":
        errors.append("COMPOSER_HANDOFF_NOT_BOUND")
    if "prompt_constraints" in (data.get("composer_payload") or {}):
        errors.append("PROMPT_CONSTRAINTS_LEAKED_TO_COMPOSER")
    return errors


def require_negative_detection(base: dict) -> dict[str, bool]:
    cases: dict[str, bool] = {}

    x = copy.deepcopy(base)
    x["deliverable_created"]["component_tree"] = [n for n in x["deliverable_created"]["component_tree"] if n.get("component_id") != "header_search"]
    cases["missing_search"] = bool(material_errors(x))

    x = copy.deepcopy(base)
    for node in x["deliverable_created"]["component_tree"]:
        if node.get("component_id") == "service_card_template":
            node["content"]["fields"] = ["title", "provider", "call_to_action"]
    cases["missing_price"] = bool(material_errors(x))

    x = copy.deepcopy(base)
    x["deliverable_created"]["screen_definition"]["design_intent"] = ["clear", "easy_to_navigate"]
    cases["missing_professional_intent"] = bool(material_errors(x))

    x = copy.deepcopy(base)
    x["deliverable_created"]["remediation_actions"] = [{"invented": True}]
    cases["create_new_remediation"] = bool(material_errors(x))

    boundary = load_module(BOUNDARY_VALIDATOR, "s26_hp001_boundary_negative")
    x = copy.deepcopy(base)
    x["composer_payload"]["execution_id"] = "forbidden-in-composer"
    cases["composer_metadata_leak"] = bool(boundary.validate(x))

    if not all(cases.values()):
        failed = sorted(name for name, passed in cases.items() if not passed)
        raise RuntimeError("NEGATIVE_CONTROL_FALSE_PASS:" + ",".join(failed))
    return cases


def main() -> int:
    data = load_json(OUTPUT)
    receipt = load_json(RECEIPT)

    if receipt.get("schema") != "S26_HP001_MANUAL_PROFILE_EXECUTION_RECEIPT_V1":
        raise RuntimeError("EXECUTION_RECEIPT_SCHEMA_INVALID")
    if receipt.get("execution_mode") != "CURRENT_CHAT_MANUAL_PROFILE_RUN" or receipt.get("model") != "GPT-5.6 Sol":
        raise RuntimeError("MANUAL_EXECUTION_IDENTITY_INVALID")
    if receipt.get("candidate_sha256") != sha256(OUTPUT):
        raise RuntimeError("MANUAL_OUTPUT_SHA_MISMATCH")
    if receipt.get("input_sha256") != sha256(INPUT):
        raise RuntimeError("MANUAL_INPUT_SHA_MISMATCH")
    if any(receipt.get(key) is not False for key in ("automatic_model_runtime_used", "model_weight_acquisition_performed", "paid_fallback_performed", "production_effect")):
        raise RuntimeError("MANUAL_EXECUTION_SAFETY_BOUNDARY_INVALID")

    context = data.get("governance_envelope", {}).get("context", {})
    if context.get("test_id") != receipt.get("test_id") or context.get("input_sha256") != receipt.get("input_sha256"):
        raise RuntimeError("OUTPUT_RECEIPT_CONTEXT_MISMATCH")
    if context.get("frozen_source_sha") != receipt.get("frozen_source_sha"):
        raise RuntimeError("OUTPUT_FROZEN_SOURCE_MISMATCH")
    if context.get("card_resolution") != "NO_CARD_GOVERNED":
        raise RuntimeError("OUTPUT_CARD_RESOLUTION_MISMATCH")

    ui = load_module(UI_VALIDATOR, "s26_hp001_ui_validator")
    ui_errors = ui.validate(data)
    if ui_errors:
        raise RuntimeError("UI_ARCHITECT_VALIDATOR_FAILED:" + json.dumps(ui_errors, ensure_ascii=False, sort_keys=True))

    boundary = load_module(BOUNDARY_VALIDATOR, "s26_hp001_boundary_validator")
    boundary_errors = boundary.validate(data)
    if boundary_errors:
        raise RuntimeError("COMPOSER_BOUNDARY_FAILED:" + json.dumps(boundary_errors, ensure_ascii=False, sort_keys=True))

    semantic_errors = material_errors(data)
    if semantic_errors:
        raise RuntimeError("MATERIAL_REQUIREMENTS_FAILED:" + ",".join(semantic_errors))

    negatives = require_negative_detection(data)
    result = {
        "gate": "S26_HP001_OUTPUT_F_H_V1",
        "result": "PASS",
        "stages": {
            "F_PROFILE_EXECUTION": "PASS_CURRENT_CHAT_MANUAL_PROFILE_RUN",
            "G_CONTRACT_SHAPE": "PASS_CANONICAL_VALIDATORS",
            "H_MATERIAL_REQUIREMENTS": "PASS",
        },
        "candidate_sha256": sha256(OUTPUT),
        "input_sha256": sha256(INPUT),
        "negative_controls": negatives,
        "independent_semantic_review_performed": False,
        "automatic_model_runtime_used": False,
        "model_weight_acquisition_performed": False,
        "paid_fallback_performed": False,
        "production_effect": False,
        "claim_ceiling": receipt.get("claim_ceiling"),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
