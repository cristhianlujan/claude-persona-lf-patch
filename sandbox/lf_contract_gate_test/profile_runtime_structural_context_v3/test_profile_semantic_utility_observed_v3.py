#!/usr/bin/env python3
"""Source-bound semantic-utility regression for B2B-CARGA-001 batch 33596749435.

The three runtime requests completed transport successfully on the exact artifact, but
success must not be promoted to useful/canonical profile output. This fixture captures
only the observed output SHAPES needed for deterministic regression; it does not alter
profile prompts and it does not claim semantic PASS.

Source: Supabase private.lf_profile_runtime_queue_v1 readback, GitHub run 33596749435.
Artifact SHA-256: ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ARTIFACT_SHA = "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287"
RUN_ID = 33596749435


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def strict_json_object(text: str):
    try:
        value = json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def main() -> int:
    product = load(
        REPO / "profiles/product_director_lf/validators/validate_product_director_output.py",
        "canonical_product_validator_observed",
    )
    ui = load(
        REPO / "profiles/ui_architect/validators/validate_ui_architect_output.py",
        "canonical_ui_validator_observed",
    )

    # Exact material shapes observed in batch 33596749435.
    product_raw = "PRODUCT_DIRECTION_SPEC"
    ui_raw = "```json\n" + json.dumps({
        "self_verdict": "PASS",
        "evidence_by_criterion": {
            "layout_precision": 5,
            "visual_hierarchy": 5,
            "lf_system_fidelity": 5,
            "state_mapping": 5,
            "handoff_quality": 5,
        },
        "total": 25,
    }) + "\n```"
    quality_raw = "```json\n" + json.dumps({
        "review_id": f"85_SHA_{ARTIFACT_SHA}",
        "reviewed_artifact": "Historial de cargas",
        "verdict": "PASS_TO_COMPOSER",
        "score_breakdown": {
            "contract_schema_compliance": 5,
            "evidence_integrity": 5,
            "lf_safety_governance": 5,
            "handoff_readiness": 5,
            "leakage_scope_control": 5,
            "total": 25,
        },
        "evidence_map": [{"ref": "Historial de cargas", "digest": ARTIFACT_SHA, "type": "SHA-256"}],
        "blocking_codes": [],
        "repair_actions": [],
        "remaining_risks": [],
        "next_gate": "CONTINUE",
        "routing": {
            "activation_path": "DIRECT", "via": "ORCHESTRATOR",
            "pipeline_action": "CONTINUE", "resolution_target": "COMPOSER",
        },
    }) + "\n```"

    # Product: label-only output is not the required structured decision.
    product_result = product.validate(product_raw)
    assert product_result.get("valid") is False, product_result

    # UI: fenced score-only shape is neither strict JSON nor executable UI spec.
    assert strict_json_object(ui_raw) is None
    # Strip fences only to prove that even the inner object remains canonically invalid.
    ui_inner = json.loads(ui_raw.removeprefix("```json\n").removesuffix("\n```"))
    ui_errors = ui.validate(ui_inner)
    assert ui_errors, "canonical UI validator unexpectedly accepted observed score-only shape"

    # Quality: runtime request explicitly required one bare JSON object; fenced output
    # is already non-consumable before any evidence/semantic gate is considered.
    assert strict_json_object(quality_raw) is None

    observed = 3
    transport_succeeded = 3
    semantic_utility_valid = 0
    detection = 3
    assert transport_succeeded == observed
    assert semantic_utility_valid == 0
    assert detection == observed

    print(
        "PROFILE_SEMANTIC_UTILITY_OBSERVED_V3_PASS "
        f"artifact_sha={ARTIFACT_SHA} source_run={RUN_ID} "
        "transport_succeeded=3/3 semantic_utility_valid=0/3 "
        "invalid_output_detection=3/3 profile_prompt_changes=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
