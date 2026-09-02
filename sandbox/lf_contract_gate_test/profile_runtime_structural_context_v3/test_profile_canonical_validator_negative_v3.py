#!/usr/bin/env python3
"""Bind observed PROFILE_RUNTIME V3 negative shapes to canonical profile validators.

No profile prompt is modified. This only prevents transport success from being promoted
when canonical validators reject the material output shape.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    product = load(
        REPO / "profiles/product_director_lf/validators/validate_product_director_output.py",
        "canonical_product_validator",
    )
    ui = load(
        REPO / "profiles/ui_architect/validators/validate_ui_architect_output.py",
        "canonical_ui_validator",
    )

    # Same failure families observed on B2B-CARGA-001 batch 33596749435.
    product_label_only = "PRODUCT_DIRECTION_SPEC"
    ui_score_only = {"self_verdict": "PASS", "total": 25, "evidence_by_criterion": {}}

    # Raw label is not even a JSON object, so the canonical Product validator receives
    # the parsed semantic equivalent as a non-object and must fail closed.
    product_result = product.validate(product_label_only)
    ui_errors = ui.validate(ui_score_only)

    assert product_result.get("valid") is False, product_result
    assert "NOT_OBJECT" in set(product_result.get("blocking_codes") or []), product_result
    assert ui_errors, "UI canonical validator unexpectedly accepted score-only output"
    ui_codes = {e.get("code") for e in ui_errors if isinstance(e, dict)}
    assert "OUTPUT_TYPE_INVALID" in ui_codes or "DELIVERABLE_MISSING" in ui_codes, ui_errors

    print(
        "PROFILE_CANONICAL_VALIDATOR_NEGATIVE_V3_PASS "
        "product_observed_shape_rejected=1/1 ui_observed_shape_rejected=1/1 "
        "profile_prompt_changes=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
