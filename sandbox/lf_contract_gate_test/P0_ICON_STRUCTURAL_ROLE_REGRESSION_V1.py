#!/usr/bin/env python3
"""Causal regression for structural icon ownership/materiality.

Invokes product reconciliation directly. The fixtures prove the general
relationship invariants and negative controls; no screen coordinates or icon
names are hard-coded into product logic.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPTS))

from p0_icon_structural_roles_v1 import reconcile_icon_structural_roles  # noqa: E402


def base_element(element_id: str, element_type: str, x: int, y: int, w: int, h: int, text=None) -> dict:
    return {
        "element_id": element_id,
        "element_type": element_type,
        "region": {"x": x, "y": y, "width": w, "height": h},
        "visible_text": text,
        "semantic_role": "material_icon" if element_type == "ICON" else "visible_copy",
        "functional_intent": None,
        "functional_intent_classification": "NOT_OBSERVABLE" if element_type == "ICON" else None,
        "parent_id": "ROOT",
    }


def icon_uncertainty(element_id: str, extra_code: str | None = None) -> list[dict]:
    out = [{"element_id": element_id, "code": "ICON_FUNCTION_NOT_OBSERVABLE"}]
    if extra_code:
        out.append({"element_id": element_id, "code": extra_code})
    return out


def run_case(elements: list[dict], uncertainties: list[dict]) -> dict:
    return reconcile_icon_structural_roles({"elements": elements, "reader_uncertainties": uncertainties})


def main() -> int:
    # Positive A: icon center inside an existing control inherits parent ownership.
    parent = base_element("CTRL", "CONTROL_REGION", 100, 100, 300, 60)
    child = base_element("ICON-A", "ICON", 115, 115, 20, 20)
    unrelated = {"element_id": "TEXT-X", "code": "OCR_DISAGREEMENT"}
    contained = run_case([parent, child], icon_uncertainty("ICON-A") + [unrelated])
    child_after = next(e for e in contained["elements"] if e["element_id"] == "ICON-A")
    codes = [(u.get("element_id"), u.get("code")) for u in contained["reader_uncertainties"]]
    if child_after.get("parent_id") != "CTRL" or child_after.get("semantic_role") != "control_visual_affordance":
        raise SystemExit(f"FAIL_ICON_STRUCTURAL_PARENT:{child_after!r}")
    if ("ICON-A", "ICON_FUNCTION_NOT_OBSERVABLE") in codes or ("TEXT-X", "OCR_DISAGREEMENT") not in codes:
        raise SystemExit(f"FAIL_ICON_STRUCTURAL_PARENT_DEBT:{codes!r}")

    # Positive B: compact region substantially duplicated by confirmed text does not need an independent icon function.
    icon = base_element("ICON-B", "ICON", 200, 200, 20, 20)
    text = base_element("TEXT-B", "TEXT", 199, 199, 24, 22, "Ab")
    overlap = run_case([icon, text], icon_uncertainty("ICON-B", "OTHER_ICON_FINDING"))
    icon_after = next(e for e in overlap["elements"] if e["element_id"] == "ICON-B")
    codes = [(u.get("element_id"), u.get("code")) for u in overlap["reader_uncertainties"]]
    if icon_after.get("functional_intent_classification") != "NOT_APPLICABLE_TEXT_OVERLAP":
        raise SystemExit(f"FAIL_ICON_STRUCTURAL_TEXT_OVERLAP:{icon_after!r}")
    if ("ICON-B", "ICON_FUNCTION_NOT_OBSERVABLE") in codes or ("ICON-B", "OTHER_ICON_FINDING") not in codes:
        raise SystemExit(f"FAIL_ICON_STRUCTURAL_TEXT_OVERLAP_DEBT:{codes!r}")

    # Negative A: nearby but not contained / not overlapped must remain unresolved.
    standalone = base_element("ICON-C", "ICON", 10, 10, 20, 20)
    nearby_control = base_element("CTRL-C", "CONTROL_REGION", 40, 5, 200, 50)
    nearby_text = base_element("TEXT-C", "TEXT", 35, 12, 100, 15, "Nearby")
    negative = run_case([standalone, nearby_control, nearby_text], icon_uncertainty("ICON-C"))
    neg_codes = [(u.get("element_id"), u.get("code")) for u in negative["reader_uncertainties"]]
    if ("ICON-C", "ICON_FUNCTION_NOT_OBSERVABLE") not in neg_codes:
        raise SystemExit(f"FAIL_ICON_STRUCTURAL_NEARBY_FALSE_RESOLUTION:{neg_codes!r}")

    # Negative B: only ICON elements are eligible; glyph/text uncertainty is untouched.
    glyph = base_element("GLYPH", "ICON_OR_GLYPH", 110, 110, 20, 20)
    glyph_case = run_case([parent, glyph], [{"element_id": "GLYPH", "code": "OCR_DISAGREEMENT"}])
    if glyph_case["reader_uncertainties"] != [{"element_id": "GLYPH", "code": "OCR_DISAGREEMENT"}]:
        raise SystemExit(f"FAIL_ICON_STRUCTURAL_GLYPH_MUTATION:{glyph_case['reader_uncertainties']!r}")

    print(json.dumps({
        "result": "PASS",
        "ekb_code": "EKB-P0-027",
        "contained_icon_inherits_parent": True,
        "text_overlap_icon_function_debt_removed": True,
        "nearby_standalone_icon_preserved": True,
        "unrelated_uncertainties_preserved": True,
        "interaction_functions_confirmed": 0,
        "production_authorized": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
