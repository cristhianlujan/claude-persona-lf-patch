#!/usr/bin/env python3
"""Bounded P0 V3 parent-containment remediation.

Only INFERRED elements may be reparented. Confirmed geometry is never expanded
or rewritten to make an inferred child fit. The nearest existing ancestor that
contains the observed child geometry within the governed tolerance is selected.
"""
from __future__ import annotations
from typing import Any
from p0_visual_fidelity_v3 import _contains, _r, _viewport_size, geometry_profile


def repair_inferred_parent_containment(candidate: dict[str, Any], config: dict[str, Any] | None = None) -> list[str]:
    elements = candidate.get("elements", [])
    byid = {e.get("element_id"): e for e in elements}
    tol = float((config or {}).get("geometry", {}).get("parent_containment_tolerance_px", 10))
    vw, vh = _viewport_size(candidate)
    repaired: list[str] = []
    for element in elements:
        if element.get("classification") != "INFERRED" or element.get("element_type") == "SCREEN":
            continue
        parent_id = element.get("parent_id")
        parent = byid.get(parent_id)
        if not parent or _contains(_r(parent), _r(element), tol):
            continue
        visited = {parent_id}
        ancestor = byid.get(parent.get("parent_id"))
        while ancestor and ancestor.get("element_id") not in visited:
            ancestor_id = ancestor.get("element_id")
            visited.add(ancestor_id)
            if _contains(_r(ancestor), _r(element), tol):
                element["parent_id"] = ancestor_id
                element["geometry"] = geometry_profile(element, ancestor, vw, vh)
                element.setdefault("machine_remediation_trace", []).append({
                    "strategy": "INFERRED_PARENT_REASSIGNMENT",
                    "from_parent_id": parent_id,
                    "to_parent_id": ancestor_id,
                    "reason": "PARENT_CONTAINMENT_CONFLICT",
                })
                repaired.append(str(element.get("element_id")))
                break
            ancestor = byid.get(ancestor.get("parent_id"))
    return repaired
