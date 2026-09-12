#!/usr/bin/env python3
"""Deterministic downstream quality non-regression guards for PROFILE_RUNTIME V3.

This test does not modify profile prompts. It ensures transport/runtime success cannot be
counted as quality success when a canonical output contract is not met.
"""
from __future__ import annotations

import json
import re

PRODUCT_REQUIRED_ROOT = {
    "worker", "output_type", "deliverable_created", "score",
    "handoff_to_next", "self_verdict", "traceability",
}
UI_REQUIRED_ROOT = {"deliverable_created", "score", "handoff_to_next", "self_verdict"}
QUALITY_REQUIRED_ROOT = {
    "review_id", "reviewed_artifact", "verdict", "score_breakdown",
    "evidence_map", "blocking_codes", "repair_actions", "remaining_risks",
    "next_gate", "routing",
}


def strict_json_object(text: str):
    try:
        value = json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def product_contract_valid(text: str) -> bool:
    obj = strict_json_object(text)
    return bool(obj is not None and PRODUCT_REQUIRED_ROOT <= set(obj))


def quality_contract_valid(text: str) -> bool:
    obj = strict_json_object(text)
    return bool(obj is not None and QUALITY_REQUIRED_ROOT <= set(obj))


def ui_contract_valid(text: str) -> bool:
    obj = strict_json_object(text)
    return bool(obj is not None and UI_REQUIRED_ROOT <= set(obj))


def main() -> int:
    # Regression shapes observed on the same B2B-CARGA-001 artifact.
    product_label_only = "PRODUCT_DIRECTION_SPEC"
    quality_fenced = "```json\n" + json.dumps({
        "review_id": "r", "reviewed_artifact": "a", "verdict": "PASS_TO_COMPOSER",
        "score_breakdown": {}, "evidence_map": [], "blocking_codes": [],
        "repair_actions": [], "remaining_risks": [], "next_gate": "CONTINUE",
        "routing": {},
    }) + "\n```"
    ui_score_only = json.dumps({"self_verdict": "PASS", "total": 25, "evidence_by_criterion": {}})

    assert not product_contract_valid(product_label_only)
    assert not quality_contract_valid(quality_fenced)
    assert not ui_contract_valid(ui_score_only)

    valid_product = {key: {} for key in PRODUCT_REQUIRED_ROOT}
    valid_product.update({"worker": "product_director_lf", "output_type": "PRODUCT_DIRECTION_SPEC", "self_verdict": "PASS"})
    valid_quality = {key: [] for key in QUALITY_REQUIRED_ROOT}
    valid_quality.update({
        "review_id": "r", "reviewed_artifact": "a", "verdict": "BLOCK_PIPELINE",
        "score_breakdown": {}, "next_gate": "STOP", "routing": {},
    })
    valid_ui = {"deliverable_created": {}, "score": {}, "handoff_to_next": {}, "self_verdict": "PASS"}

    assert product_contract_valid(json.dumps(valid_product))
    assert quality_contract_valid(json.dumps(valid_quality))
    assert ui_contract_valid(json.dumps(valid_ui))

    print(
        "PROFILE_QUALITY_NONREGRESSION_V3_PASS "
        "transport_success_not_quality_success=3/3 "
        "canonical_root_contract_positive_controls=3/3 "
        "critical_regressions_count=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
