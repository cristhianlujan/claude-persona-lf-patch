#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BOUNDARY_PATH = ROOT / "profiles/ui_architect/validators/validate_composer_payload_boundary.py"
V5_VALIDATOR_PATH = ROOT / "profiles/ui_architect/validators/validate_ui_architect_output.py"
RUN_E_PATH = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/raw_output.json"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def codes(errors):
    return {item.get("code") for item in errors if isinstance(item, dict)}


def make_v6(run_e, boundary):
    data = copy.deepcopy(run_e)
    context = data["deliverable_created"].pop("governance_context")
    data["output_contract_version"] = boundary.VERSION
    data["governance_envelope"] = {
        "schema": boundary.ENVELOPE_SCHEMA,
        "render_policy": "NON_RENDER",
        "context": context,
    }
    data["handoff_to_next"]["payload_ref"] = "composer_payload"
    data["composer_payload"] = boundary.build_composer_payload(data["deliverable_created"])
    return data


def assert_s26_current_page_not_prebound(composer_payload):
    pagination = composer_payload["state_map"]["pagination"]
    assert pagination.get("selected_page") == "NOT_PREBOUND"
    assert "current_page" not in pagination
    pagination_action = composer_payload["remediation_actions"][0]
    desired = str(pagination_action["execution"]["desired_value"]).replace(" ", "")
    assert "current_page=" not in desired


def assert_guard_rejects_prebound_current_page(composer_payload):
    state_prebound = copy.deepcopy(composer_payload)
    state_prebound["state_map"]["pagination"]["current_page"] = 1
    try:
        assert_s26_current_page_not_prebound(state_prebound)
    except AssertionError:
        pass
    else:
        raise AssertionError("state current_page prebind must be rejected")

    execution_prebound = copy.deepcopy(composer_payload)
    execution_prebound["remediation_actions"][0]["execution"]["desired_value"] = "current_page=1; page_count=1"
    try:
        assert_s26_current_page_not_prebound(execution_prebound)
    except AssertionError:
        pass
    else:
        raise AssertionError("execution current_page prebind must be rejected")


def main():
    boundary = load_module(BOUNDARY_PATH, "composer_boundary")
    v5 = load_module(V5_VALIDATOR_PATH, "ui_v5_validator")
    run_e = json.loads(RUN_E_PATH.read_text(encoding="utf-8"))
    passed = 0

    # 1. Historical holdout: Run E remains an unchanged valid V5 governed artifact.
    assert "output_contract_version" not in run_e
    assert v5.validate(run_e) == []
    passed += 1

    # 2. Positive V6 structural boundary.
    v6 = make_v6(run_e, boundary)
    assert boundary.validate(v6) == []
    passed += 1

    # 3. Missing Composer payload fails closed.
    missing = make_v6(run_e, boundary)
    missing.pop("composer_payload")
    assert "COMPOSER_PAYLOAD_MISSING" in codes(boundary.validate(missing))
    passed += 1

    # 4. Any semantic divergence from the deterministic projection fails.
    mismatch = make_v6(run_e, boundary)
    mismatch["composer_payload"]["screen_definition"]["screen_name"] = "Different screen"
    assert "COMPOSER_PAYLOAD_PROJECTION_MISMATCH" in codes(boundary.validate(mismatch))
    passed += 1

    # 5. Provider/repository refs cannot leak into Composer payload.
    github_leak = make_v6(run_e, boundary)
    github_leak["composer_payload"]["risk_controls"].append("github://owner/repo@deadbeef/path")
    assert "COMPOSER_INTERNAL_VALUE_LEAK" in codes(boundary.validate(github_leak))
    passed += 1

    # 6. Evidence source refs cannot leak into Composer payload.
    source_ref_leak = make_v6(run_e, boundary)
    source_ref_leak["composer_payload"]["remediation_actions"][0]["precision_basis"]["source_refs"] = ["EVIDENCE"]
    assert "COMPOSER_INTERNAL_KEY_LEAK" in codes(boundary.validate(source_ref_leak))
    passed += 1

    # 7. V6 forbids global governance metadata inside deliverable_created.
    nested_governance = make_v6(run_e, boundary)
    nested_governance["deliverable_created"]["governance_context"] = copy.deepcopy(nested_governance["governance_envelope"]["context"])
    assert "DELIVERABLE_GOVERNANCE_CONTEXT_FORBIDDEN_V6" in codes(boundary.validate(nested_governance))
    passed += 1

    # 8. Handoff must bind Composer to the clean payload and not the full root/deliverable.
    bad_handoff = make_v6(run_e, boundary)
    bad_handoff["handoff_to_next"]["payload_ref"] = "deliverable_created"
    assert "COMPOSER_HANDOFF_PAYLOAD_REF_INVALID" in codes(boundary.validate(bad_handoff))
    passed += 1

    # 9. Operational worker/score/verdict metadata cannot be inserted into Composer payload.
    worker_leak = make_v6(run_e, boundary)
    worker_leak["composer_payload"]["worker"] = "ui_architect"
    assert "COMPOSER_INTERNAL_KEY_LEAK" in codes(boundary.validate(worker_leak))
    passed += 1

    # 10. Artifact digest is audit metadata and is stripped from screen_definition projection.
    digest_leak = make_v6(run_e, boundary)
    digest_leak["composer_payload"]["screen_definition"]["artifact_sha256"] = "0" * 64
    assert "COMPOSER_INTERNAL_KEY_LEAK" in codes(boundary.validate(digest_leak))
    passed += 1

    # 11. Future internal structural keys fail closed instead of passing by denylist omission.
    unknown_component_key = make_v6(run_e, boundary)
    unknown_component_key["deliverable_created"]["component_tree"][0]["internal_trace_context"] = {"opaque": "x"}
    unknown_component_key["composer_payload"] = boundary.build_composer_payload(unknown_component_key["deliverable_created"])
    result_codes = codes(boundary.validate(unknown_component_key))
    assert "COMPOSER_COMPONENT_KEY_NOT_ALLOWED" in result_codes
    assert "COMPOSER_INTERNAL_KEY_LEAK" in result_codes
    passed += 1

    # 12. Future internal metadata nested in extensible content is still rejected recursively.
    unknown_content_metadata = make_v6(run_e, boundary)
    unknown_content_metadata["deliverable_created"]["component_tree"][0]["content"]["runtime_source_context"] = "opaque"
    unknown_content_metadata["composer_payload"] = boundary.build_composer_payload(unknown_content_metadata["deliverable_created"])
    assert "COMPOSER_INTERNAL_KEY_LEAK" in codes(boundary.validate(unknown_content_metadata))
    passed += 1

    # 13. Semantic holdout: boundary preserves non-canonical rules and does not prebind current_page.
    # Safety prose may mention the token; only executable/state binding is forbidden in this S26 fixture.
    semantic = make_v6(run_e, boundary)
    actions = semantic["deliverable_created"]["remediation_actions"]
    assert [a["precision_basis"]["mode"] for a in actions] == ["RELATIVE_GUIDANCE", "RELATIVE_GUIDANCE"]
    assert all(a["precision_basis"]["proposal_status"] == "PROPOSED_NOT_CANONICAL" for a in actions)
    assert_s26_current_page_not_prebound(semantic["composer_payload"])
    assert_guard_rejects_prebound_current_page(semantic["composer_payload"])
    passed += 1

    print(f"UI_COMPOSER_BOUNDARY_TESTS_PASS {passed}/13")


if __name__ == "__main__":
    main()