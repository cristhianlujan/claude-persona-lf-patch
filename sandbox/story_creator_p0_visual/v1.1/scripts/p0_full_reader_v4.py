#!/usr/bin/env python3
from __future__ import annotations

import collections
import hashlib
import statistics
from difflib import SequenceMatcher

import cv2
import pytesseract
from pytesseract import Output

from p0_visual_atomicity_v4 import (
    annotate_evidence_purity,
    bbox_union,
    crop_evidence_ref,
    crop_sha256,
    detect_compact_visuals,
    overlap_fraction,
    segment_ocr_line_items,
    vertical_overlap_ratio,
)


def region_ref(source_sha: str, region: dict) -> str:
    raw = f"{source_sha}:{region['x']}:{region['y']}:{region['width']}:{region['height']}".encode()
    return "p0://v4/source-region/" + hashlib.sha256(raw).hexdigest()


def observation_ref(source_sha: str, psm: int, region: dict, text: str) -> str:
    raw = f"{source_sha}:{psm}:{region['x']}:{region['y']}:{region['width']}:{region['height']}:{norm(text)}".encode()
    return "p0://v4/ocr-observation/" + hashlib.sha256(raw).hexdigest()


def norm(value: str) -> str:
    return " ".join(value.casefold().split())


def iou(a: dict, b: dict) -> float:
    x1 = max(a["x"], b["x"])
    y1 = max(a["y"], b["y"])
    x2 = min(a["x"] + a["width"], b["x"] + b["width"])
    y2 = min(a["y"] + a["height"], b["y"] + b["height"])
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    if not intersection:
        return 0.0
    return intersection / float(a["width"] * a["height"] + b["width"] * b["height"] - intersection)


def overlap_primary(a: dict, b: dict) -> float:
    x1 = max(a["x"], b["x"])
    y1 = max(a["y"], b["y"])
    x2 = min(a["x"] + a["width"], b["x"] + b["width"])
    y2 = min(a["y"] + a["height"], b["y"] + b["height"])
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    return intersection / max(1, a["width"] * a["height"])


def _compact_nonword_segment(item: dict) -> bool:
    """Protect compact symbol-like OCR without treating short alphabetic words as icons."""
    text = str(item.get("text") or "").strip()
    region = item.get("region") or {}
    width = int(region.get("width", 0))
    height = int(region.get("height", 0))
    aspect = width / max(1, height)
    compact = len(text) <= 4 and 0.65 <= aspect <= 1.55 and max(width, height) <= 32
    if not compact:
        return False
    return len(text) <= 1 or not text.isalpha()


def _same_visual_text_line(left_item: dict, right_item: dict) -> bool:
    left_item, right_item = sorted(
        (left_item, right_item),
        key=lambda candidate: (int(candidate["region"]["x"]), int(candidate["region"]["y"])),
    )
    left = left_item["region"]
    right = right_item["region"]
    gap = int(right["x"]) - (int(left["x"]) + int(left["width"]))
    min_height = max(1, min(int(left["height"]), int(right["height"])))
    baseline_delta = abs(
        (int(left["y"]) + int(left["height"]))
        - (int(right["y"]) + int(right["height"]))
    )
    gap_limit = max(24, int(round(0.90 * min_height)))
    baseline_limit = max(5, int(round(0.35 * min_height)))
    if _compact_nonword_segment(left_item) or _compact_nonword_segment(right_item):
        return False
    return (
        0 <= gap <= gap_limit
        and vertical_overlap_ratio(left, right) >= 0.65
        and baseline_delta <= baseline_limit
    )


def _merge_component(component: list[dict]) -> dict:
    component = sorted(
        component,
        key=lambda item: (int(item["region"]["x"]), int(item["region"]["y"])),
    )
    if len(component) == 1:
        return component[0]
    merged = dict(component[0])
    token_count = sum(max(1, int(item.get("token_count") or 1)) for item in component)
    merged["confidence"] = sum(
        float(item.get("confidence") or 0.0) * max(1, int(item.get("token_count") or 1))
        for item in component
    ) / max(1, token_count)
    merged["text"] = " ".join(str(item.get("text") or "").strip() for item in component).strip()
    merged["region"] = bbox_union(item["region"] for item in component)
    merged["token_count"] = token_count
    for field in ("source_tokens", "source_token_ids", "source_token_regions"):
        values = []
        for item in component:
            values.extend(list(item.get(field) or []))
        merged[field] = values
    line_keys: list[str] = []
    for item in component:
        for key in item.get("source_line_keys") or []:
            if key not in line_keys:
                line_keys.append(key)
    merged["source_line_keys"] = line_keys
    excluded: list[str] = []
    for item in component:
        for token_id in item.get("excluded_compact_token_ids") or []:
            if token_id not in excluded:
                excluded.append(token_id)
    if excluded:
        merged["excluded_compact_token_ids"] = excluded
    merged["cross_line_merge_justification"] = "GEOMETRIC_GRAPH_CONNECTED_COMPONENT"
    return merged


def graph_reconcile_ocr_segments(items: list[dict]) -> list[dict]:
    """Reconstruct visual text independently of OCR block/line partition topology."""
    if len(items) <= 1:
        return list(items)
    adjacency: list[set[int]] = [set() for _ in items]
    for left_index in range(len(items)):
        for right_index in range(left_index + 1, len(items)):
            if _same_visual_text_line(items[left_index], items[right_index]):
                adjacency[left_index].add(right_index)
                adjacency[right_index].add(left_index)
    seen: set[int] = set()
    merged: list[dict] = []
    for start in range(len(items)):
        if start in seen:
            continue
        seen.add(start)
        stack = [start]
        component: list[dict] = []
        while stack:
            index = stack.pop()
            component.append(items[index])
            for neighbor in adjacency[index]:
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)
        merged.append(_merge_component(component))
    return sorted(
        merged,
        key=lambda item: (int(item["region"]["y"]), int(item["region"]["x"])),
    )


def ocr_lines(image, psm: int) -> list[dict]:
    data = pytesseract.image_to_data(image, lang="spa", config=f"--psm {psm}", output_type=Output.DICT)
    grouped: dict[tuple[int, int, int], list[dict]] = {}
    for index, raw_text in enumerate(data["text"]):
        text = (raw_text or "").strip()
        if not text:
            continue
        try:
            confidence = float(data["conf"][index])
        except (TypeError, ValueError):
            confidence = -1.0
        if confidence < 0:
            continue
        key = (int(data["block_num"][index]), int(data["par_num"][index]), int(data["line_num"][index]))
        grouped.setdefault(key, []).append(
            {
                "text": text,
                "confidence": confidence,
                "x": int(data["left"][index]),
                "y": int(data["top"][index]),
                "width": int(data["width"][index]),
                "height": int(data["height"][index]),
                "block_id": key[0],
                "paragraph_id": key[1],
                "line_id": key[2],
                "token_id": "OCR-%s-%s-%s-%s-%s-%s" % (
                    psm,
                    int(data.get("page_num", [1] * len(data["text"]))[index]),
                    key[0],
                    key[1],
                    key[2],
                    int(data.get("word_num", [index] * len(data["text"]))[index]),
                ),
            }
        )

    output: list[dict] = []
    for key, items in grouped.items():
        segments = segment_ocr_line_items(items)
        for segment_index, segment in enumerate(segments, 1):
            region = bbox_union({"x": item["x"], "y": item["y"], "width": item["width"], "height": item["height"]} for item in segment)
            output.append(
                {
                    "text": " ".join(item["text"] for item in segment),
                    "confidence": sum(item["confidence"] for item in segment) / len(segment),
                    "region": region,
                    "block_id": key[0],
                    "paragraph_id": key[1],
                    "line_id": key[2],
                    "segment_index": segment_index,
                    "origin_psm": psm,
                    "token_count": len(segment),
                    "source_tokens": [item["text"] for item in segment],
                    "source_token_ids": [item["token_id"] for item in segment],
                    "source_token_regions": [
                        {key: item[key] for key in ("x", "y", "width", "height")} for item in segment
                    ],
                    "source_line_keys": [f"{psm}:{key[0]}:{key[1]}:{key[2]}"],
                    "partition_boundary_before": "STRONG_GEOMETRIC_GAP" if segment_index > 1 else None,
                }
            )
    return graph_reconcile_ocr_segments(output)


def _refine_line_relative_geometry(line: dict) -> list[dict]:
    """Split an OCR segment when token gaps are large relative to glyph height.

    This is a second, source-agnostic atomicity guard after Tesseract line grouping.
    It prevents compact prefixes/icons and neighboring placeholders from sharing one
    crop just because the OCR engine assigned them to one line.
    """
    tokens = list(line.get("source_tokens") or [])
    token_ids = list(line.get("source_token_ids") or [])
    token_regions = list(line.get("source_token_regions") or [])
    if len(tokens) < 2 or len(tokens) != len(token_regions):
        return [line]

    order = sorted(range(len(tokens)), key=lambda i: (int(token_regions[i]["x"]), int(token_regions[i]["y"])))
    median_height = float(statistics.median(max(1, int(token_regions[i]["height"])) for i in order))
    relative_gap_limit = max(18.0, 1.75 * median_height)
    groups: list[list[int]] = [[order[0]]]
    for index in order[1:]:
        previous_index = groups[-1][-1]
        previous = token_regions[previous_index]
        current = token_regions[index]
        gap = int(current["x"]) - (int(previous["x"]) + int(previous["width"]))
        center_delta = abs(
            (int(current["y"]) + int(current["height"]) / 2)
            - (int(previous["y"]) + int(previous["height"]) / 2)
        )
        height_limit = 0.8 * max(int(current["height"]), int(previous["height"]), 1)
        strong_boundary = gap > relative_gap_limit or (gap > 12 and center_delta > height_limit)
        if strong_boundary:
            groups.append([index])
        else:
            groups[-1].append(index)

    if len(groups) == 1:
        return [line]

    refined: list[dict] = []
    for group_index, group in enumerate(groups, 1):
        item = dict(line)
        item["source_tokens"] = [tokens[i] for i in group]
        item["source_token_ids"] = [token_ids[i] for i in group if i < len(token_ids)]
        item["source_token_regions"] = [token_regions[i] for i in group]
        item["text"] = " ".join(item["source_tokens"]).strip()
        item["region"] = bbox_union(item["source_token_regions"])
        item["token_count"] = len(group)
        item["segment_index"] = group_index
        item["partition_boundary_before"] = (
            line.get("partition_boundary_before") if group_index == 1 else "RELATIVE_GEOMETRIC_GAP"
        )
        item["cross_line_merge_justification"] = None
        refined.append(item)
    return refined


def refine_ocr_geometry(items: list[dict]) -> list[dict]:
    refined: list[dict] = []
    for item in items:
        refined.extend(_refine_line_relative_geometry(item))
    return sorted(refined, key=lambda item: (int(item["region"]["y"]), int(item["region"]["x"])))


def overlapping_lines(primary: dict, alternatives: list[dict]) -> list[dict]:
    region = primary["region"]
    items = [
        item for item in alternatives
        if overlap_primary(region, item["region"]) >= 0.15 or iou(region, item["region"]) >= 0.08
    ]
    return sorted(items, key=lambda item: (item["region"]["y"], item["region"]["x"]))


def _text_similarity(a: str, b: str) -> float:
    left, right = norm(a), norm(b)
    if not left or not right:
        return 0.0
    if left in right or right in left:
        return 0.92
    return SequenceMatcher(None, left, right).ratio()


def match_alt(primary: dict, alternatives: list[dict]) -> str:
    """Return one atomic alternate observation; never concatenate siblings."""
    candidates: list[tuple[float, dict]] = []
    for item in alternatives:
        spatial = max(overlap_primary(primary["region"], item["region"]), iou(primary["region"], item["region"]))
        similarity = _text_similarity(primary.get("text") or "", item.get("text") or "")
        if spatial < 0.08 and similarity < 0.72:
            continue
        score = 0.68 * spatial + 0.32 * similarity
        candidates.append((score, item))
    if not candidates:
        return ""
    candidates.sort(key=lambda pair: (pair[0], pair[1].get("confidence", 0.0)), reverse=True)
    return " ".join((candidates[0][1].get("text") or "").split())


def _consensus_from_variants(variants: list[str]) -> tuple[str, int]:
    nonempty = [value for value in variants if norm(value)]
    if not nonempty:
        return "", 0
    counts = collections.Counter(norm(value) for value in nonempty)
    best_norm, support = counts.most_common(1)[0]
    best_text = next(value for value in nonempty if norm(value) == best_norm)
    return best_text, support


def _has_localizable_disagreement(variants: list[str]) -> bool:
    values = [norm(value) for value in variants if norm(value)]
    if len(set(values)) < 2:
        return False
    return any(
        left != right
        and abs(len(left) - len(right)) <= 2
        and SequenceMatcher(None, left, right).ratio() >= 0.78
        for index, left in enumerate(values)
        for right in values[index + 1 :]
    )


def _symbol_only_delta(base: str, candidate: str) -> bool:
    """Allow a localized reread to change only ambiguous punctuation/symbol glyphs."""
    left = " ".join(str(base or "").split())
    right = " ".join(str(candidate or "").split())
    if not left or not right or left == right:
        return False
    changed = 0
    for tag, i1, i2, j1, j2 in SequenceMatcher(None, left, right).get_opcodes():
        if tag == "equal":
            continue
        removed = left[i1:i2]
        added = right[j1:j2]
        if any(char.isalnum() for char in added):
            return False
        if tag == "delete" and any(char.isalnum() for char in removed):
            return False
        changed += max(len(removed), len(added))
    return 1 <= changed <= 2


def localized_symbol_redetection(image, line: dict, variants: list[str]) -> dict | None:
    """Reread only an uncertain local crop with an alternate OCR language model.

    The alternate model is never allowed to rewrite words. It is accepted only when
    multiple local passes agree and the delta against an existing source reading is
    limited to one or two non-alphanumeric glyphs.
    """
    if not _has_localizable_disagreement(variants):
        return None
    region = line.get("region") or {}
    if not all(key in region for key in ("x", "y", "width", "height")):
        return None
    height, width = image.shape[:2]
    pad = max(2, int(round(max(1, int(region["height"])) * 0.20)))
    x1 = max(0, int(region["x"]) - pad)
    y1 = max(0, int(region["y"]) - pad)
    x2 = min(width, int(region["x"]) + int(region["width"]) + pad)
    y2 = min(height, int(region["y"]) + int(region["height"]) + pad)
    crop = image[y1:y2, x1:x2]
    if crop.size == 0:
        return None
    enlarged = cv2.resize(crop, None, fx=4, fy=4, interpolation=cv2.INTER_CUBIC)
    readings: list[str] = []
    psms = (6, 7, 11)
    for psm in psms:
        raw = pytesseract.image_to_string(enlarged, lang="eng", config=f"--psm {psm}")
        readings.append(" ".join(str(raw or "").split()))
    candidate, support = _consensus_from_variants(readings)
    if support < 2 or not candidate:
        return None
    baselines = [value for value in variants if value]
    if not any(_symbol_only_delta(base, candidate) for base in baselines):
        return None
    return {
        "text": candidate,
        "support": support,
        "readings": readings,
        "psms": list(psms),
        "language_model": "eng",
        "region": {"x": x1, "y": y1, "width": x2 - x1, "height": y2 - y1},
        "method": "LOCALIZED_SYMBOL_REDETECTION",
    }


def grouping_signal(primary: dict, lines: dict[int, list[dict]], primary_psm: int, source_sha: str) -> tuple[bool, str, list[str], dict]:
    refs: list[str] = []
    by_psm: dict[str, int] = {}
    reconstructed_by_psm: dict[str, str] = {}
    primary_text = norm(primary.get("text") or "")
    for psm, observations in lines.items():
        matched = overlapping_lines(primary, observations)
        if psm == primary_psm and not matched:
            matched = [primary]
        by_psm[str(psm)] = len(matched)
        reconstructed = norm(match_alt(primary, observations)) if psm != primary_psm else primary_text
        reconstructed_by_psm[str(psm)] = reconstructed
        for item in matched:
            refs.append(observation_ref(source_sha, psm, item["region"], item.get("text") or ""))

    primary_count = by_psm.get(str(primary_psm), 1)
    disagreements: list[str] = []
    for psm in sorted(lines):
        if psm == primary_psm:
            continue
        text = reconstructed_by_psm.get(str(psm), "")
        count = by_psm.get(str(psm), 0)
        if not text or count == primary_count:
            continue
        similarity = SequenceMatcher(None, primary_text, text).ratio() if primary_text else 1.0
        if similarity < 0.72:
            disagreements.append(text)

    corroborated = any(
        SequenceMatcher(None, left, right).ratio() >= 0.80
        for index, left in enumerate(disagreements)
        for right in disagreements[index + 1 :]
    )
    consistency = not corroborated
    fallback = observation_ref(source_sha, primary_psm, primary["region"], primary.get("text") or "")
    group_id = "TG-" + hashlib.sha256(("|".join(sorted(set(refs))) or fallback).encode()).hexdigest()[:16]
    return consistency, group_id, sorted(set(refs)), by_psm


def cv_objects(image, text_regions: list[dict]) -> list[dict]:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)))
    raw_contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    closed_contours, _ = cv2.findContours(closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    contours = list(raw_contours) + list(closed_contours)
    raw: list[dict] = []
    for contour in contours:
        x, y, width, height = cv2.boundingRect(contour)
        area = width * height
        if area < 900 or area > 100000 or width < 16 or height < 10:
            continue
        region = {"x": int(x), "y": int(y), "width": int(width), "height": int(height)}
        polygon = cv2.approxPolyDP(contour, 0.02 * cv2.arcLength(contour, True), True)
        region["_polygon_sides"] = len(polygon)
        region["_contour_fill"] = float(cv2.contourArea(contour)) / max(1, area)
        control_shape = (
            36 <= height <= 80
            and width >= 180
            and region["_polygon_sides"] == 4
            and region["_contour_fill"] >= 0.75
        )
        large_nontext_shape = area >= 3000 and height >= 40
        if not (control_shape or large_nontext_shape):
            continue
        if any(
            overlap_primary(region, text_region) > 0.75
            and overlap_primary(text_region, region) > 0.75
            for text_region in text_regions
        ):
            continue
        raw.append(region)
    raw.sort(key=lambda region: region["width"] * region["height"], reverse=True)
    kept: list[dict] = []
    for region in raw:
        if any(iou(region, existing) > 0.82 for existing in kept):
            continue
        kept.append(region)
        if len(kept) >= 120:
            break
    return kept


def _base_element(element_id: str, element_type: str, region: dict, parent_id: str | None, evidence_refs: list[str]) -> dict:
    return {
        "element_id": element_id,
        "element_type": element_type,
        "visible_text": None,
        "classification": "CONFIRMED",
        "confidence": 1.0,
        "region": region,
        "crop_region": dict(region),
        "parent_id": parent_id,
        "evidence_refs": evidence_refs,
        "bbox_reproducible": True,
        "style": {},
        "style_provenance": {},
        "independent_redetection": True,
        "business_rule_claim": None,
        "business_rule_visible_evidence": False,
        "risk_zone": None,
    }


def _compact_overlap(line: dict, compact: list[dict]) -> bool:
    if len((line.get("text") or "").strip()) > 4:
        return False
    return any(overlap_fraction(line["region"], item["region"]) >= 0.55 for item in compact)


def _exclude_compact_tokens(line: dict, compact: list[dict]) -> dict | None:
    tokens = list(line.get("source_tokens") or [])
    token_ids = list(line.get("source_token_ids") or [])
    token_regions = list(line.get("source_token_regions") or [])
    if not tokens or len(tokens) != len(token_regions):
        return None if _compact_overlap(line, compact) else line
    kept_indices: list[int] = []
    excluded_ids: list[str] = []
    for index, token_region in enumerate(token_regions):
        is_compact = any(overlap_fraction(token_region, item["region"]) >= 0.48 for item in compact)
        if is_compact:
            if index < len(token_ids):
                excluded_ids.append(token_ids[index])
        else:
            kept_indices.append(index)
    if not excluded_ids:
        return line
    if not kept_indices:
        return None
    filtered = dict(line)
    filtered["source_tokens"] = [tokens[index] for index in kept_indices]
    filtered["source_token_ids"] = [token_ids[index] for index in kept_indices if index < len(token_ids)]
    filtered["source_token_regions"] = [token_regions[index] for index in kept_indices]
    filtered["text"] = " ".join(filtered["source_tokens"])
    filtered["region"] = bbox_union(filtered["source_token_regions"])
    filtered["token_count"] = len(kept_indices)
    filtered["excluded_compact_token_ids"] = excluded_ids
    return filtered


def _classify_object_region(region: dict) -> tuple[str, str]:
    if (
        36 <= region["height"] <= 80
        and region["width"] >= 180
        and int(region.get("_polygon_sides", 0)) == 4
        and float(region.get("_contour_fill", 0.0)) >= 0.75
    ):
        return "CONTROL_REGION", "form_control_region"
    return "VISUAL_OBJECT", "visual_object"


def _assign_relationships(elements: list[dict]) -> None:
    controls = [element for element in elements if element.get("element_type") == "CONTROL_REGION"]
    checkboxes = [element for element in elements if element.get("element_type") == "CHECKBOX"]
    for element in elements:
        if not element.get("visible_text"):
            continue
        region = element["region"]
        center_x = region["x"] + region["width"] / 2
        center_y = region["y"] + region["height"] / 2
        containing = [
            control for control in controls
            if control["region"]["x"] <= center_x <= control["region"]["x"] + control["region"]["width"]
            and control["region"]["y"] <= center_y <= control["region"]["y"] + control["region"]["height"]
        ]
        if containing:
            containing.sort(key=lambda control: control["region"]["width"] * control["region"]["height"])
            element["parent_id"] = containing[0]["element_id"]
            element["semantic_role"] = "control_visible_text"
            continue
        described = [
            control for control in controls
            if control["region"]["x"] <= center_x <= control["region"]["x"] + control["region"]["width"]
            and 0 <= control["region"]["y"] - (region["y"] + region["height"]) <= 36
        ]
        if described:
            described.sort(key=lambda control: control["region"]["y"] - (region["y"] + region["height"]))
            element["semantic_role"] = "field_label"
            element["describes_control_id"] = described[0]["element_id"]
            element["field_group_id"] = described[0]["element_id"]
            continue
        for checkbox in checkboxes:
            box = checkbox["region"]
            dx = region["x"] - (box["x"] + box["width"])
            checkbox_cy = box["y"] + box["height"] / 2
            if 4 <= dx <= 110 and abs(center_y - checkbox_cy) <= max(20, region["height"] * 1.5):
                element["semantic_role"] = "control_label"
                element["describes_control_id"] = checkbox["element_id"]
                element["field_group_id"] = checkbox["element_id"]
                break


def full_reader(source_path: str, ctx: dict) -> dict:
    image = cv2.imread(source_path)
    if image is None:
        raise ValueError("SOURCE_DECODE_FAILED")
    height, width = image.shape[:2]
    strict = bool((ctx.get("remediation_state") or {}).get("strict_mode"))
    primary_psm = 3 if strict else 11
    psms = (3, 11, 12)
    lines = {psm: refine_ocr_geometry(ocr_lines(image, psm)) for psm in psms}
    compact = detect_compact_visuals(image, lines[primary_psm])
    lines = {
        psm: [filtered for line in observations if (filtered := _exclude_compact_tokens(line, compact)) is not None]
        for psm, observations in lines.items()
    }
    primary = lines[primary_psm]
    if strict:
        union = list(primary)
        for alternate in lines[11]:
            duplicate = any(
                max(iou(alternate["region"], existing["region"]), overlap_primary(alternate["region"], existing["region"])) >= 0.38
                and _text_similarity(alternate.get("text") or "", existing.get("text") or "") >= 0.58
                for existing in union
            )
            if not duplicate:
                union.append(alternate)
        primary = sorted(union, key=lambda item: (item["region"]["y"], item["region"]["x"]))

    root = _base_element(
        "V4-ROOT",
        "CONTAINER",
        {"x": 0, "y": 0, "width": width, "height": height},
        None,
        ["p0://v4/source/" + ctx["source_sha256"]],
    )
    elements = [root]
    uncertainties: list[dict] = []
    localized_redetection_count = 0

    text_ordinal = 0
    for line in primary:
        if _compact_overlap(line, compact):
            continue
        text_ordinal += 1
        line_psm = int(line.get("origin_psm", primary_psm))
        variants = [line["text"] if psm == line_psm else match_alt(line, lines[psm]) for psm in psms]
        nonempty = [value for value in variants if value]
        best_text, consensus_support = _consensus_from_variants(nonempty)
        localized = localized_symbol_redetection(image, line, variants) if strict else None
        evidence_variants = list(variants)
        consensus_source = "OCR_PSM_CONSENSUS"
        if localized:
            localized_redetection_count += 1
            evidence_variants.extend(localized["readings"])
            best_text = localized["text"]
            consensus_support = int(localized["support"])
            consensus_source = localized["method"]
        exact_agreement = sum(norm(value) == norm(line["text"]) for value in nonempty)
        consensus_available = consensus_support >= 2
        selected_matches_primary = bool(best_text) and norm(best_text) == norm(line["text"])
        stable = consensus_available and selected_matches_primary and float(line["confidence"]) >= 65
        text = best_text if (strict and consensus_available and best_text) else line["text"]
        classification = "CONFIRMED" if (not strict and line["confidence"] >= 45) or (strict and stable) else "INFERRED"
        element_type = "TEXT"
        consensus = best_text if (not strict or consensus_available) else ""
        region = line["region"]
        aspect = region["width"] / max(1, region["height"])
        glyph_shape = len(text.strip()) <= 1 and 0.65 <= aspect <= 1.55 and max(region["width"], region["height"]) <= 32
        numeric_short = sum(char.isdigit() for char in text) >= 2
        if strict and len(text.strip()) <= 3 and (glyph_shape or (consensus_support < 3 and not numeric_short)):
            element_type = "ICON_OR_GLYPH"
            text = None
            classification = "INFERRED"
            consensus = ""
        graphic_score = 0.82 if (not strict and text and len(text.strip()) <= 3 and consensus_support < 2) else 0.05
        semantic_role = "control_visible_text" if text and text.strip().startswith("+") and any(char.isdigit() for char in text) else "visible_copy"
        group_ok, group_id, source_refs, group_counts = grouping_signal(line, lines, line_psm, ctx["source_sha256"])
        subrole = "GLYPH" if glyph_shape and element_type in {"TEXT", "LABEL"} else None
        risk = "LEGAL" if text and len(text) >= 120 else ("DENSE" if region["width"] * region["height"] >= 18000 and text and len(text) >= 50 else None)
        crop_ref = crop_evidence_ref(ctx["source_sha256"], image, region, "OCR_TEXT")
        element = {
            "element_id": f"V4-T-{text_ordinal:04d}",
            "element_type": element_type,
            "visible_text": text,
            "classification": classification,
            "confidence": round(max(0, min(1, line["confidence"] / 100.0)), 6),
            "region": region,
            "crop_region": dict(region),
            "crop_sha256": crop_sha256(image, region),
            "parent_id": "V4-ROOT",
            "semantic_role": semantic_role,
            "subcomponent_role": subrole,
            "evidence_refs": [region_ref(ctx["source_sha256"], region), crop_ref],
            "source_observation_refs": source_refs,
            "text_group_consistency": group_ok,
            "text_group_id": group_id,
            "text_group_observation_counts": group_counts,
            "text_lineage": {
                "block_id": line.get("block_id"),
                "origin_psm": line_psm,
                "paragraph_id": line.get("paragraph_id"),
                "line_id": line.get("line_id"),
                "segment_index": line.get("segment_index"),
                "token_count": line.get("token_count"),
                "source_tokens": line.get("source_tokens") or [],
                "source_token_ids": line.get("source_token_ids") or [],
                "source_token_regions": line.get("source_token_regions") or [],
                "excluded_compact_token_ids": line.get("excluded_compact_token_ids") or [],
                "source_line_keys": line.get("source_line_keys") or [],
                "partition_boundary_before": line.get("partition_boundary_before"),
                "cross_line_merge_justification": line.get("cross_line_merge_justification"),
            },
            "ocr_variants": evidence_variants,
            "ocr_consensus_text": consensus,
            "ocr_read_count": len(evidence_variants),
            "ocr_empty_reads": sum(not value for value in evidence_variants),
            "ocr_agreement_count": exact_agreement,
            "ocr_consensus_support": consensus_support,
            "ocr_consensus_source": consensus_source,
            "localized_redetection": localized,
            "graphic_score": graphic_score,
            "brand_mark_score": 0.0,
            "business_rule_claim": None,
            "business_rule_visible_evidence": False,
            "risk_zone": risk,
            "bbox_reproducible": True,
            "style": {},
            "style_provenance": {},
            "independent_redetection": stable,
            "redetection_status": "REDETECTED" if stable else "AMBIGUOUS",
        }
        elements.append(element)
        if element_type == "TEXT" and not stable:
            uncertainties.append({"element_id": element["element_id"], "code": "OCR_DISAGREEMENT", "region": region})
        if element_type == "TEXT" and not group_ok:
            uncertainties.append(
                {
                    "element_id": element["element_id"],
                    "code": "TEXT_GROUPING_DISAGREEMENT",
                    "region": region,
                    "observation_counts": group_counts,
                }
            )

    text_regions = [element["region"] for element in elements if element.get("visible_text")]
    for ordinal, region in enumerate(cv_objects(image, text_regions), 1):
        if any(overlap_fraction(region, item["region"]) >= 0.72 for item in compact):
            continue
        element_type, semantic_role = _classify_object_region(region)
        region = {key: region[key] for key in ("x", "y", "width", "height")}
        element = _base_element(
            f"V4-O-{ordinal:04d}",
            element_type,
            region,
            "V4-ROOT",
            [region_ref(ctx["source_sha256"], region), crop_evidence_ref(ctx["source_sha256"], image, region, "CV_OBJECT")],
        )
        element.update(
            {
                "classification": "INFERRED" if element_type == "VISUAL_OBJECT" else "CONFIRMED",
                "confidence": 0.75 if element_type == "VISUAL_OBJECT" else 0.93,
                "semantic_role": semantic_role,
                "crop_sha256": crop_sha256(image, region),
                "source_observation_refs": [region_ref(ctx["source_sha256"], region)],
                "brand_mark_score": 0.0,
            }
        )
        elements.append(element)

    control_ordinal = icon_ordinal = 0
    for item in compact:
        region = item["region"]
        if item["kind"] == "CONTROL":
            control_ordinal += 1
            element = _base_element(
                f"V4-C-{control_ordinal:04d}",
                item["control_type"],
                region,
                "V4-ROOT",
                [region_ref(ctx["source_sha256"], region), crop_evidence_ref(ctx["source_sha256"], image, region, "COMPACT_CONTROL")],
            )
            element.update(
                {
                    "confidence": item["confidence"],
                    "semantic_role": "repeated_control",
                    "control_type": item["control_type"],
                    "repeated_control_group_id": item["repeated_control_group_id"],
                    "detector": item["detector"],
                    "crop_sha256": crop_sha256(image, region),
                }
            )
        else:
            icon_ordinal += 1
            element = _base_element(
                f"V4-I-{icon_ordinal:04d}",
                "ICON",
                region,
                "V4-ROOT",
                [region_ref(ctx["source_sha256"], region), crop_evidence_ref(ctx["source_sha256"], image, region, "MATERIAL_ICON")],
            )
            element.update(
                {
                    "confidence": item["confidence"],
                    "semantic_role": "material_icon",
                    "visual_shape": item["visual_shape"],
                    "shape_classification": "CONFIRMED",
                    "functional_intent": None,
                    "functional_intent_classification": "NOT_OBSERVABLE",
                    "detector": item["detector"],
                    "crop_sha256": crop_sha256(image, region),
                }
            )
            uncertainties.append(
                {
                    "element_id": element["element_id"],
                    "code": "ICON_FUNCTION_NOT_OBSERVABLE",
                    "region": region,
                    "visual_shape": item["visual_shape"],
                }
            )
        elements.append(element)

    _assign_relationships(elements)
    annotate_evidence_purity(elements)
    compact_counts = collections.Counter(item["kind"] for item in compact)
    repeated_counts = collections.Counter(
        item.get("repeated_control_group_id") for item in compact if item.get("repeated_control_group_id")
    )
    return {
        "schema_version": "p0-full-reader-v4/v1",
        "execution_id": ctx["reader_execution_id"],
        "pass_id": ctx["pass_id"],
        "reader_execution_id": ctx["reader_execution_id"],
        "source_sha256": ctx["source_sha256"],
        "width": width,
        "height": height,
        "fresh_source_read": True,
        "reader_origin": "SOURCE_PIXELS",
        "reader_profile": "STRICT_CONSENSUS" if strict else "RAW_DISCOVERY",
        "elements": elements,
        "raw_observations": {
            "primary_psm": primary_psm,
            "line_counts": {str(key): len(value) for key, value in lines.items()},
            "cv_object_count": sum(element.get("element_type") in {"VISUAL_OBJECT", "CONTROL_REGION"} for element in elements),
            "compact_control_count": compact_counts.get("CONTROL", 0),
            "material_icon_count": compact_counts.get("ICON", 0),
            "repeated_control_group_counts": dict(sorted(repeated_counts.items())),
            "ocr_engine_family": "TESSERACT",
            "ocr_geometry_refiner": "RELATIVE_GAP_V2",
            "localized_symbol_redetection_count": localized_redetection_count,
            "localized_symbol_model": "TESSERACT_ENG_PSM_6_7_11",
            "object_detector_family": "OPENCV_CANNY_CONTOUR_HIERARCHY",
        },
        "reader_uncertainties": uncertainties,
    }
