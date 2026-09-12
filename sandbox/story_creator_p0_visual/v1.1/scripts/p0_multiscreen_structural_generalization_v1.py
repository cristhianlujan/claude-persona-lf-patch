#!/usr/bin/env python3
"""Screen-agnostic structural generalization for the P0 V4 visual reader.

This module deliberately avoids product/screen literals and fixed coordinates.
It extends the existing reader with two pixel/geometry invariants discovered on
an independent second screen:

1. repeated large input cells are controls, not arbitrary visual objects/text;
2. OCR repeated punctuation may be normalized to bullet-mask glyphs only when
   the source pixels independently show aligned filled compact components.

Neither invariant infers interaction behavior or business rules.
"""
from __future__ import annotations

import copy
import statistics

import cv2

import p0_full_reader_v4 as _base_reader


def _iou(a: dict, b: dict) -> float:
    x1 = max(int(a["x"]), int(b["x"]))
    y1 = max(int(a["y"]), int(b["y"]))
    x2 = min(int(a["x"]) + int(a["width"]), int(b["x"]) + int(b["width"]))
    y2 = min(int(a["y"]) + int(a["height"]), int(b["y"]) + int(b["height"]))
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    union = int(a["width"]) * int(a["height"]) + int(b["width"]) * int(b["height"]) - inter
    return inter / max(1, union)


def _overlap_fraction(a: dict, b: dict) -> float:
    x1 = max(int(a["x"]), int(b["x"]))
    y1 = max(int(a["y"]), int(b["y"]))
    x2 = min(int(a["x"]) + int(a["width"]), int(b["x"]) + int(b["width"]))
    y2 = min(int(a["y"]) + int(a["height"]), int(b["y"]) + int(b["height"]))
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    return inter / max(1, int(a["width"]) * int(a["height"]))


def detect_segmented_input_cells(image) -> list[dict]:
    """Detect 4-10 aligned large closed cells without assigning OTP/PIN meaning."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    raw: list[dict] = []
    for contour in contours:
        x, y, width, height = cv2.boundingRect(contour)
        if not (
            48 <= width <= 110
            and 55 <= height <= 125
            and 0.52 <= width / max(1, height) <= 1.28
        ):
            continue
        perimeter = cv2.arcLength(contour, True)
        polygon = cv2.approxPolyDP(contour, 0.04 * perimeter, True)
        fill = float(cv2.contourArea(contour)) / max(1, width * height)
        if not (4 <= len(polygon) <= 8 and cv2.isContourConvex(polygon) and fill >= 0.70):
            continue
        raw.append(
            {
                "x": int(x),
                "y": int(y),
                "width": int(width),
                "height": int(height),
                "fill": fill,
            }
        )

    raw.sort(key=lambda region: region["width"] * region["height"], reverse=True)
    candidates: list[dict] = []
    for region in raw:
        if any(_iou(region, kept) >= 0.72 for kept in candidates):
            continue
        candidates.append(region)

    groups: list[list[dict]] = []
    consumed: set[int] = set()
    for seed_index, seed in enumerate(candidates):
        if seed_index in consumed:
            continue
        seed_cy = seed["y"] + seed["height"] / 2
        peers: list[tuple[int, dict]] = []
        for index, region in enumerate(candidates):
            cy = region["y"] + region["height"] / 2
            if (
                abs(cy - seed_cy) <= max(8.0, 0.12 * max(seed["height"], region["height"]))
                and 0.75 <= region["width"] / max(1, seed["width"]) <= 1.33
                and 0.75 <= region["height"] / max(1, seed["height"]) <= 1.33
            ):
                peers.append((index, region))
        if len(peers) < 4:
            continue
        peers.sort(key=lambda pair: pair[1]["x"])
        median_width = float(statistics.median(region["width"] for _, region in peers))
        runs: list[list[tuple[int, dict]]] = []
        current: list[tuple[int, dict]] = []
        for item in peers:
            if not current:
                current = [item]
                continue
            previous = current[-1][1]
            previous_cx = previous["x"] + previous["width"] / 2
            current_cx = item[1]["x"] + item[1]["width"] / 2
            center_gap = current_cx - previous_cx
            if 0.85 * median_width <= center_gap <= 2.20 * median_width:
                current.append(item)
            else:
                if len(current) >= 4:
                    runs.append(current)
                current = [item]
        if len(current) >= 4:
            runs.append(current)

        for run in runs:
            if not 4 <= len(run) <= 10:
                continue
            groups.append([region for _, region in run])
            consumed.update(index for index, _ in run)

    controls: list[dict] = []
    for ordinal, group in enumerate(groups, 1):
        group_id = f"RCG-SI-{ordinal:03d}"
        for region in group:
            controls.append(
                {
                    "kind": "CONTROL",
                    "control_type": "SEGMENTED_INPUT_CELL",
                    "repeated_control_group_id": group_id,
                    "region": {key: int(region[key]) for key in ("x", "y", "width", "height")},
                    "detector": "CV_REPEATED_LARGE_INPUT_CELLS",
                    "confidence": 0.99,
                }
            )
    return controls


def normalize_repeated_mask_token(image, region: dict, raw_text: str) -> str | None:
    """Return bullet-mask text only when repeated OCR punctuation is contradicted by filled-dot pixels."""
    token = str(raw_text or "").strip()
    if not (3 <= len(token) <= 8 and len(set(token)) == 1 and token[0] in {"+", "x", "X", "*"}):
        return None
    height, width = image.shape[:2]
    x1 = max(0, int(region.get("x", 0)))
    y1 = max(0, int(region.get("y", 0)))
    x2 = min(width, x1 + max(0, int(region.get("width", 0))))
    y2 = min(height, y1 + max(0, int(region.get("height", 0))))
    crop = image[y1:y2, x1:x2]
    if crop.size == 0:
        return None
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY) if crop.ndim == 3 else crop
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    count, _, stats, centroids = cv2.connectedComponentsWithStats(binary, 8)
    components: list[dict] = []
    for index in range(1, count):
        x, y, component_width, component_height, area = (int(value) for value in stats[index])
        if area < 3:
            continue
        fill = area / max(1, component_width * component_height)
        aspect = component_width / max(1, component_height)
        components.append(
            {
                "x": x,
                "y": y,
                "width": component_width,
                "height": component_height,
                "area": area,
                "fill": fill,
                "aspect": aspect,
                "cx": float(centroids[index][0]),
                "cy": float(centroids[index][1]),
            }
        )
    if len(components) != len(token):
        return None
    if not all(0.58 <= component["fill"] <= 1.0 and 0.55 <= component["aspect"] <= 1.60 for component in components):
        return None
    median_height = float(statistics.median(component["height"] for component in components))
    if max(component["cy"] for component in components) - min(component["cy"] for component in components) > max(2.0, 0.45 * median_height):
        return None
    ordered = sorted(components, key=lambda component: component["cx"])
    median_width = float(statistics.median(component["width"] for component in ordered))
    gaps = [ordered[index + 1]["cx"] - ordered[index]["cx"] for index in range(len(ordered) - 1)]
    if gaps and min(gaps) < 0.90 * median_width:
        return None
    return "•" * len(token)


def apply_pixel_mask_normalization(candidate: dict, image) -> dict:
    out = copy.deepcopy(candidate)
    changed_elements: list[str] = []
    normalized_regions: list[dict] = []
    for element in out.get("elements", []):
        if element.get("element_type") != "TEXT" or not element.get("visible_text"):
            continue
        lineage = element.get("text_lineage") if isinstance(element.get("text_lineage"), dict) else {}
        tokens = list(lineage.get("source_tokens") or [])
        regions = list(lineage.get("source_token_regions") or [])
        if len(tokens) != len(regions):
            continue
        normalizations: list[dict] = []
        visible = str(element.get("visible_text") or "")
        variants = [str(value or "") for value in (element.get("ocr_variants") or [])]
        consensus = str(element.get("ocr_consensus_text") or "")
        for index, (token, region) in enumerate(zip(tokens, regions)):
            normalized = normalize_repeated_mask_token(image, region, token)
            if normalized is None:
                continue
            original = str(token)
            tokens[index] = normalized
            visible = visible.replace(original, normalized, 1)
            variants = [value.replace(original, normalized, 1) for value in variants]
            consensus = consensus.replace(original, normalized, 1)
            evidence = {
                "code": "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
                "original_ocr_token": original,
                "normalized_visible_token": normalized,
                "region": {key: int(region.get(key, 0)) for key in ("x", "y", "width", "height")},
                "basis": "SOURCE_PIXELS_CONNECTED_COMPONENT_GEOMETRY",
            }
            normalizations.append(evidence)
            normalized_regions.append(copy.deepcopy(evidence["region"]))
        if not normalizations:
            continue
        lineage["source_tokens"] = tokens
        element["text_lineage"] = lineage
        element["visible_text"] = visible
        element["ocr_variants"] = variants
        element["ocr_consensus_text"] = consensus
        element["pixel_glyph_normalizations"] = normalizations
        element["independent_redetection"] = True
        element["redetection_status"] = "PIXEL_GLYPH_NORMALIZED"
        nonempty = {" ".join(value.casefold().split()) for value in variants if value.strip()}
        if len(nonempty) <= 1:
            out["reader_uncertainties"] = [
                uncertainty
                for uncertainty in list(out.get("reader_uncertainties") or [])
                if not (
                    uncertainty.get("element_id") == element.get("element_id")
                    and uncertainty.get("code") == "OCR_DISAGREEMENT"
                )
            ]
        changed_elements.append(str(element.get("element_id")))
    if changed_elements:
        out["structural_generalization"] = {
            **(out.get("structural_generalization") or {}),
            "pixel_mask_normalized_element_ids": changed_elements,
            "pixel_mask_normalized_regions": normalized_regions,
        }
    return out


if not hasattr(_base_reader, "_lf_multiscreen_original_detect_compact_visuals"):
    _base_reader._lf_multiscreen_original_detect_compact_visuals = _base_reader.detect_compact_visuals
_ORIGINAL_DETECT_COMPACT = _base_reader._lf_multiscreen_original_detect_compact_visuals


def _enhanced_detect_compact_visuals(image, text_regions: list[dict]) -> list[dict]:
    base = list(_ORIGINAL_DETECT_COMPACT(image, text_regions))
    segmented = detect_segmented_input_cells(image)
    for item in segmented:
        if any(_overlap_fraction(item["region"], existing["region"]) >= 0.72 for existing in base):
            continue
        base.append(item)
    return base


_base_reader.detect_compact_visuals = _enhanced_detect_compact_visuals


def full_reader(source_path: str, ctx: dict) -> dict:
    image = cv2.imread(source_path)
    if image is None:
        raise ValueError("SOURCE_DECODE_FAILED")
    candidate = _base_reader.full_reader(source_path, ctx)
    segmented = [
        element for element in candidate.get("elements", [])
        if element.get("control_type") == "SEGMENTED_INPUT_CELL"
    ]
    candidate = apply_pixel_mask_normalization(candidate, image)
    if segmented:
        candidate["structural_generalization"] = {
            **(candidate.get("structural_generalization") or {}),
            "segmented_input_cell_count": len(segmented),
            "segmented_input_group_ids": sorted({str(element.get("repeated_control_group_id")) for element in segmented}),
            "interaction_functions_confirmed": 0,
        }
    return candidate
