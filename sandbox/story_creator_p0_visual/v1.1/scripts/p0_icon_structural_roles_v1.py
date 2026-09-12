#!/usr/bin/env python3
"""Conservative structural ownership for compact visual elements.

This module does not classify icon identity and does not infer click behavior.
It only removes an independent icon-function question when geometry already
proves that the compact visual belongs to an existing control, or when the
compact visual is substantially duplicated by an existing text observation.
"""
from __future__ import annotations

import copy

TEXT_OVERLAP_MIN = 0.80


def _region(item: dict) -> dict:
    region = item.get("region") or {}
    return {key: float(region.get(key, 0)) for key in ("x", "y", "width", "height")}


def _center(region: dict) -> tuple[float, float]:
    return region["x"] + region["width"] / 2, region["y"] + region["height"] / 2


def _center_inside(inner: dict, outer: dict) -> bool:
    cx, cy = _center(inner)
    return (
        outer["x"] <= cx <= outer["x"] + outer["width"]
        and outer["y"] <= cy <= outer["y"] + outer["height"]
    )


def _overlap_primary(primary: dict, other: dict) -> float:
    x1 = max(primary["x"], other["x"])
    y1 = max(primary["y"], other["y"])
    x2 = min(primary["x"] + primary["width"], other["x"] + other["width"])
    y2 = min(primary["y"] + primary["height"], other["y"] + other["height"])
    intersection = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    return intersection / max(1.0, primary["width"] * primary["height"])


def reconcile_icon_structural_roles(candidate: dict) -> dict:
    """Return a copy with only structurally redundant icon-function debt removed."""
    out = copy.deepcopy(candidate)
    elements = list(out.get("elements") or [])
    controls = [element for element in elements if element.get("element_type") == "CONTROL_REGION"]
    texts = [
        element
        for element in elements
        if element.get("element_type") == "TEXT" and element.get("visible_text")
    ]
    resolved_ids: set[str] = set()

    for element in elements:
        if element.get("element_type") != "ICON":
            continue
        element_id = str(element.get("element_id") or "")
        icon_region = _region(element)

        overlapping_text = [
            text for text in texts
            if _overlap_primary(icon_region, _region(text)) >= TEXT_OVERLAP_MIN
        ]
        if overlapping_text:
            overlapping_text.sort(
                key=lambda text: _overlap_primary(icon_region, _region(text)),
                reverse=True,
            )
            text = overlapping_text[0]
            element["semantic_role"] = "text_overlap_visual_fragment"
            element["functional_intent"] = None
            element["functional_intent_classification"] = "NOT_APPLICABLE_TEXT_OVERLAP"
            element["structural_role_resolution"] = {
                "code": "TEXT_OVERLAP_NO_INDEPENDENT_ICON_FUNCTION",
                "evidence_element_id": text.get("element_id"),
                "overlap_primary": round(_overlap_primary(icon_region, _region(text)), 6),
            }
            resolved_ids.add(element_id)
            continue

        containing = [control for control in controls if _center_inside(icon_region, _region(control))]
        if containing:
            containing.sort(key=lambda control: _region(control)["width"] * _region(control)["height"])
            control = containing[0]
            element["parent_id"] = control.get("element_id")
            element["semantic_role"] = "control_visual_affordance"
            element["functional_intent"] = None
            element["functional_intent_classification"] = "INHERITED_PARENT_CONTROL"
            element["structural_role_resolution"] = {
                "code": "INHERIT_PARENT_CONTROL_NO_INDEPENDENT_ICON_FUNCTION",
                "evidence_element_id": control.get("element_id"),
            }
            resolved_ids.add(element_id)

    if resolved_ids:
        out["reader_uncertainties"] = [
            uncertainty
            for uncertainty in list(out.get("reader_uncertainties") or [])
            if not (
                uncertainty.get("code") == "ICON_FUNCTION_NOT_OBSERVABLE"
                and uncertainty.get("element_id") in resolved_ids
            )
        ]
        out["icon_structural_role_resolution"] = {
            "schema_version": "p0-icon-structural-role-resolution/v1",
            "resolved_count": len(resolved_ids),
            "resolved_element_ids": sorted(resolved_ids),
            "interaction_functions_confirmed": 0,
        }
    return out
