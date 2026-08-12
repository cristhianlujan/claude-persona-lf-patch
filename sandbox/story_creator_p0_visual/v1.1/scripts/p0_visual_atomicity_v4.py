#!/usr/bin/env python3
"""General visual atomicity primitives for the P0 V4 source reader.

The helpers in this module are deliberately source-agnostic.  They use OCR token
lineage, geometry, contour hierarchy and repeated-control structure; no screen
literal or fixed coordinate is embedded here.
"""
from __future__ import annotations

import hashlib
import statistics
from collections import defaultdict
from typing import Iterable

import cv2


def bbox_union(items: Iterable[dict]) -> dict:
    boxes = list(items)
    if not boxes:
        return {"x": 0, "y": 0, "width": 0, "height": 0}
    x1 = min(int(r["x"]) for r in boxes)
    y1 = min(int(r["y"]) for r in boxes)
    x2 = max(int(r["x"]) + int(r["width"]) for r in boxes)
    y2 = max(int(r["y"]) + int(r["height"]) for r in boxes)
    return {"x": x1, "y": y1, "width": x2 - x1, "height": y2 - y1}


def intersection_area(a: dict, b: dict) -> int:
    x1 = max(int(a.get("x", 0)), int(b.get("x", 0)))
    y1 = max(int(a.get("y", 0)), int(b.get("y", 0)))
    x2 = min(int(a.get("x", 0)) + int(a.get("width", 0)), int(b.get("x", 0)) + int(b.get("width", 0)))
    y2 = min(int(a.get("y", 0)) + int(a.get("height", 0)), int(b.get("y", 0)) + int(b.get("height", 0)))
    return max(0, x2 - x1) * max(0, y2 - y1)


def overlap_fraction(a: dict, b: dict) -> float:
    return intersection_area(a, b) / max(1, int(a.get("width", 0)) * int(a.get("height", 0)))


def vertical_overlap_ratio(a: dict, b: dict) -> float:
    top = max(int(a.get("y", 0)), int(b.get("y", 0)))
    bottom = min(int(a.get("y", 0)) + int(a.get("height", 0)), int(b.get("y", 0)) + int(b.get("height", 0)))
    return max(0, bottom - top) / max(1, min(int(a.get("height", 0)), int(b.get("height", 0))))


def segment_ocr_line_items(items: list[dict]) -> list[list[dict]]:
    """Split one OCR line only at a strong geometric/control boundary.

    Normal word gaps remain one semantic text block.  Large column/control gaps
    split independent labels or inputs even when Tesseract assigned one line.
    """
    if not items:
        return []
    ordered = sorted(items, key=lambda z: (int(z["x"]), int(z["y"])))
    median_height = float(statistics.median(max(1, int(z["height"])) for z in ordered))
    gap_limit = max(24.0, 3.0 * median_height)
    groups: list[list[dict]] = [[ordered[0]]]
    for item in ordered[1:]:
        previous = groups[-1][-1]
        gap = int(item["x"]) - (int(previous["x"]) + int(previous["width"]))
        center_delta = abs(
            (int(item["y"]) + int(item["height"]) / 2)
            - (int(previous["y"]) + int(previous["height"]) / 2)
        )
        height_limit = 0.8 * max(int(item["height"]), int(previous["height"]), 1)
        compact_trailing_glyph = (
            len(str(item.get("text") or "").strip()) == 1
            and int(item["height"]) <= 0.72 * max(1, int(previous["height"]))
            and gap >= 8
        )
        strong_boundary = gap > gap_limit or (gap > 12 and center_delta > height_limit) or compact_trailing_glyph
        if strong_boundary:
            groups.append([item])
        else:
            groups[-1].append(item)
    return groups


def crop_sha256(image, region: dict) -> str:
    height, width = image.shape[:2]
    x1 = max(0, int(region.get("x", 0)))
    y1 = max(0, int(region.get("y", 0)))
    x2 = min(width, x1 + max(0, int(region.get("width", 0))))
    y2 = min(height, y1 + max(0, int(region.get("height", 0))))
    crop = image[y1:y2, x1:x2]
    return hashlib.sha256(crop.tobytes()).hexdigest()


def crop_evidence_ref(source_sha256: str, image, region: dict, kind: str) -> str:
    digest = crop_sha256(image, region)
    bbox = ",".join(str(int(region[k])) for k in ("x", "y", "width", "height"))
    return f"p0://v4/source-crop/{source_sha256}/{digest}/{kind}/{bbox}"


def _descendants(index: int, hierarchy) -> list[int]:
    if hierarchy is None:
        return []
    out: list[int] = []
    for child, row in enumerate(hierarchy[0]):
        parent = int(row[3])
        while parent >= 0:
            if parent == index:
                out.append(child)
                break
            parent = int(hierarchy[0][parent][3])
    return out


def _looks_like_lock(index: int, boxes: list[dict], hierarchy) -> bool:
    outer = boxes[index]
    width, height = outer["width"], outer["height"]
    if not (16 <= width <= 42 and 20 <= height <= 50 and 0.5 <= width / max(1, height) <= 1.05):
        return False
    children = [boxes[i] for i in _descendants(index, hierarchy)]
    if len(children) < 3:
        return False
    ox, oy = outer["x"], outer["y"]
    body = [
        b for b in children
        if b["width"] >= 0.55 * width
        and 0.22 * height <= b["height"] <= 0.65 * height
        and b["y"] - oy >= 0.30 * height
    ]
    arch = [
        b for b in children
        if 0.24 * width <= b["width"] <= 0.72 * width
        and 0.15 * height <= b["height"] <= 0.48 * height
        and b["y"] - oy <= 0.38 * height
        and abs((b["x"] + b["width"] / 2) - (ox + width / 2)) <= 0.22 * width
    ]
    keyhole = [
        b for b in children
        if b["width"] <= 0.32 * width
        and b["height"] <= 0.36 * height
        and b["y"] - oy >= 0.42 * height
    ]
    return bool(body and arch and keyhole)


def _text_to_right(region: dict, text_regions: list[dict]) -> bool:
    right = int(region["x"]) + int(region["width"])
    cy = int(region["y"]) + int(region["height"]) / 2
    for item in text_regions:
        r = item.get("region", item)
        dx = int(r.get("x", 0)) - right
        text_cy = int(r.get("y", 0)) + int(r.get("height", 0)) / 2
        if 4 <= dx <= 110 and abs(text_cy - cy) <= max(18, 1.25 * int(r.get("height", 0))):
            return True
    return False


def _text_near(region: dict, text_regions: list[dict]) -> bool:
    """Require a nearby text/control context without depending on its wording."""
    left = int(region["x"])
    right = left + int(region["width"])
    top = int(region["y"])
    bottom = top + int(region["height"])
    cx = (left + right) / 2
    cy = (top + bottom) / 2
    for item in text_regions:
        r = item.get("region", item)
        r_left = int(r.get("x", 0))
        r_right = r_left + int(r.get("width", 0))
        r_top = int(r.get("y", 0))
        r_bottom = r_top + int(r.get("height", 0))
        r_cx = (r_left + r_right) / 2
        r_cy = (r_top + r_bottom) / 2
        horizontal_neighbor = min(abs(r_left - right), abs(left - r_right)) <= 420 and abs(r_cy - cy) <= 34
        vertical_neighbor = min(abs(r_top - bottom), abs(top - r_bottom)) <= 62 and abs(r_cx - cx) <= 85
        if horizontal_neighbor or vertical_neighbor:
            return True
    return False


def _covered_by_long_text(region: dict, text_regions: list[dict]) -> bool:
    for item in text_regions:
        r = item.get("region", item)
        if overlap_fraction(region, r) < 0.55:
            continue
        clean = "".join(char for char in str(item.get("text") or "") if char.isalnum())
        source_tokens = [str(token) for token in (item.get("source_tokens") or [])]
        first_raw = source_tokens[0] if source_tokens else ""
        first_clean = "".join(char for char in first_raw if char.isalnum())
        leading_compact = (
            len(first_clean) <= 3
            and any(not char.isalnum() for char in first_raw)
            and abs(int(region.get("x", 0)) - int(r.get("x", 0))) <= 5
            and int(region.get("width", 0)) <= 0.35 * int(r.get("width", 0))
        )
        if leading_compact:
            continue
        if len(clean) > 3:
            return True
    return False


def detect_compact_visuals(image, text_regions: list[dict]) -> list[dict]:
    """Detect repeated closed-square controls and lock-shaped material icons."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    contours, hierarchy = cv2.findContours(edges, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
    boxes: list[dict] = []
    for contour in contours:
        x, y, width, height = cv2.boundingRect(contour)
        perimeter = cv2.arcLength(contour, True)
        polygon = cv2.approxPolyDP(contour, 0.04 * perimeter, True)
        boxes.append(
            {
                "x": int(x), "y": int(y), "width": int(width), "height": int(height),
                "contour_area": float(cv2.contourArea(contour)),
                "polygon_sides": len(polygon),
                "polygon_convex": bool(cv2.isContourConvex(polygon)),
            }
        )

    locks: list[dict] = []
    for index, box in enumerate(boxes):
        if _looks_like_lock(index, boxes, hierarchy):
            candidate = {
                "kind": "ICON", "visual_shape": "LOCK", "region": {k: box[k] for k in ("x", "y", "width", "height")},
                "detector": "CV_CONTOUR_HIERARCHY_LOCK", "confidence": 0.98,
            }
            if not any(overlap_fraction(candidate["region"], kept["region"]) >= 0.78 for kept in locks):
                locks.append(candidate)

    square_indices: list[int] = []
    for index, box in enumerate(boxes):
        region = {k: box[k] for k in ("x", "y", "width", "height")}
        if any(overlap_fraction(region, lock["region"]) >= 0.60 for lock in locks):
            continue
        width, height = box["width"], box["height"]
        fill = box["contour_area"] / max(1, width * height)
        if (
            14 <= width <= 31
            and 14 <= height <= 31
            and 0.72 <= width / max(1, height) <= 1.28
            and fill >= 0.55
            and box["polygon_sides"] == 4
            and box["polygon_convex"]
            and _text_to_right(region, text_regions)
        ):
            if not any(overlap_fraction(region, boxes[kept]) >= 0.78 for kept in square_indices):
                square_indices.append(index)

    groups: list[list[int]] = []
    unused = set(square_indices)
    while unused:
        seed = unused.pop()
        group = [seed]
        changed = True
        while changed:
            changed = False
            for index in list(unused):
                box = boxes[index]
                if any(
                    abs((box["x"] + box["width"] / 2) - (boxes[member]["x"] + boxes[member]["width"] / 2)) <= 5
                    and 0.72 <= box["width"] / max(1, boxes[member]["width"]) <= 1.38
                    and 0.72 <= box["height"] / max(1, boxes[member]["height"]) <= 1.38
                    for member in group
                ):
                    group.append(index)
                    unused.remove(index)
                    changed = True
        if len(group) >= 2:
            groups.append(sorted(group, key=lambda i: boxes[i]["y"]))

    controls: list[dict] = []
    for ordinal, group in enumerate(sorted(groups, key=lambda g: (boxes[g[0]]["x"], boxes[g[0]]["y"])), 1):
        group_id = f"RCG-{ordinal:03d}"
        for index in group:
            box = boxes[index]
            controls.append(
                {
                    "kind": "CONTROL", "control_type": "CHECKBOX", "repeated_control_group_id": group_id,
                    "region": {k: box[k] for k in ("x", "y", "width", "height")},
                    "detector": "CV_REPEATED_CLOSED_SQUARES", "confidence": 0.99,
                }
            )

    generic_icons: list[dict] = []
    for index, box in enumerate(boxes):
        region = {k: box[k] for k in ("x", "y", "width", "height")}
        if any(overlap_fraction(region, item["region"]) >= 0.55 for item in controls + locks):
            continue
        width, height = box["width"], box["height"]
        descendants = len(_descendants(index, hierarchy))
        structured = descendants >= 2 or (
            descendants >= 1 and box["polygon_sides"] >= 4 and box["contour_area"] >= 0.20 * width * height
        )
        if not (
            14 <= width <= 48
            and 14 <= height <= 54
            and 0.42 <= width / max(1, height) <= 1.75
            and structured
            and _text_near(region, text_regions)
            and not _covered_by_long_text(region, text_regions)
        ):
            continue
        candidate = {
            "kind": "ICON",
            "visual_shape": "UNCLASSIFIED_COMPACT",
            "region": region,
            "detector": "CV_STRUCTURED_COMPACT_REGION",
            "confidence": 0.91,
        }
        if not any(overlap_fraction(region, kept["region"]) >= 0.72 for kept in generic_icons):
            generic_icons.append(candidate)

    combined: list[dict] = []
    for item in controls + locks + generic_icons:
        if any(overlap_fraction(item["region"], kept["region"]) >= 0.75 for kept in combined):
            continue
        combined.append(item)
    return sorted(combined, key=lambda item: (item["region"]["y"], item["region"]["x"], item["kind"]))


def normalize_text(value: str | None) -> str:
    return " ".join(str(value or "").casefold().split())


def evidence_purity_issues(elements: list[dict]) -> list[dict]:
    """Recompute sibling text/crop contamination without trusting producer flags."""
    texts = [e for e in elements if normalize_text(e.get("visible_text"))]
    issues: list[dict] = []
    for element in texts:
        region = element.get("region") or {}
        crop_region = element.get("crop_region") or region
        own = normalize_text(element.get("visible_text"))
        variants = [normalize_text(v) for v in (element.get("ocr_variants") or [])]
        variants.append(normalize_text(element.get("ocr_consensus_text")))
        contaminated_by: set[str] = set()
        reasons: set[str] = set()
        for sibling in texts:
            if sibling is element:
                continue
            sibling_region = sibling.get("region") or {}
            sibling_text = normalize_text(sibling.get("visible_text"))
            same_line = vertical_overlap_ratio(region, sibling_region) >= 0.45
            disjoint = intersection_area(region, sibling_region) == 0
            if not same_line or not disjoint:
                continue
            if sibling_text not in own and any(sibling_text and sibling_text in variant for variant in variants):
                contaminated_by.add(str(sibling.get("element_id")))
                reasons.add("OCR_EXCLUSIVE_SIBLING_TEXT")
            if overlap_fraction(sibling_region, crop_region) >= 0.12:
                contaminated_by.add(str(sibling.get("element_id")))
                reasons.add("CROP_INVADES_SIBLING")
        if contaminated_by:
            issues.append(
                {
                    "element_id": element.get("element_id"),
                    "contaminating_sibling_ids": sorted(contaminated_by),
                    "reasons": sorted(reasons),
                    "crop_region": crop_region,
                }
            )
    return issues


def exclusive_partition_issues(elements: list[dict]) -> list[dict]:
    """Enforce one producer token/crop owner and justified text partitions."""
    issues: list[dict] = []
    token_owners: dict[str, list[str]] = defaultdict(list)
    crop_owners: dict[str, list[str]] = defaultdict(list)
    line_members: dict[str, list[dict]] = defaultdict(list)
    by_id = {str(element.get("element_id")): element for element in elements}
    for element in elements:
        element_id = str(element.get("element_id"))
        lineage = element.get("text_lineage") or {}
        for token_id in lineage.get("source_token_ids") or []:
            token_owners[str(token_id)].append(element_id)
        for line_key in lineage.get("source_line_keys") or []:
            line_members[str(line_key)].append(element)
        crop_region = element.get("crop_region") or element.get("region") or {}
        crop_id = None
        if element.get("crop_sha256"):
            crop_id = "%s:%s" % (
                element.get("crop_sha256"),
                ",".join(str(int(crop_region.get(key, 0))) for key in ("x", "y", "width", "height")),
            )
        if crop_id and element.get("element_type") != "CONTAINER":
            crop_owners[str(crop_id)].append(element_id)

    def documented_exception(left_id: str, right_id: str) -> bool:
        left, right = by_id.get(left_id, {}), by_id.get(right_id, {})
        related = left.get("parent_id") == right_id or right.get("parent_id") == left_id
        return related and bool(left.get("evidence_overlap_exception") or right.get("evidence_overlap_exception"))

    for token_id, owners in sorted(token_owners.items()):
        distinct = sorted(set(owners))
        if len(distinct) > 1:
            issues.append(
                {
                    "code": "SHARED_EVIDENCE_VIOLATION",
                    "element_ids": distinct,
                    "evidence_kind": "OCR_TOKEN",
                    "evidence_id": token_id,
                }
            )
    for crop_id, owners in sorted(crop_owners.items()):
        distinct = sorted(set(owners))
        violating = [
            (left, right)
            for index, left in enumerate(distinct)
            for right in distinct[index + 1 :]
            if not documented_exception(left, right)
        ]
        if violating:
            issues.append(
                {
                    "code": "SHARED_EVIDENCE_VIOLATION",
                    "element_ids": distinct,
                    "evidence_kind": "PIXEL_CROP",
                    "evidence_id": crop_id,
                }
            )

    seen_partition_sets: set[tuple[str, ...]] = set()
    for line_key, members in sorted(line_members.items()):
        distinct = {str(member.get("element_id")): member for member in members}
        if len(distinct) < 2:
            continue
        ordered = sorted(distinct.values(), key=lambda item: int((item.get("region") or {}).get("x", 0)))
        unjustified: list[str] = []
        for index, member in enumerate(ordered):
            if index == 0:
                continue
            lineage = member.get("text_lineage") or {}
            if not lineage.get("partition_boundary_before"):
                unjustified.extend((str(ordered[index - 1].get("element_id")), str(member.get("element_id"))))
        key = tuple(sorted(set(unjustified)))
        if key and key not in seen_partition_sets:
            seen_partition_sets.add(key)
            issues.append(
                {
                    "code": "UNJUSTIFIED_PARTITION",
                    "element_ids": list(key),
                    "source_line_key": line_key,
                }
            )
    return issues


def annotate_evidence_purity(elements: list[dict]) -> None:
    by_id = {issue["element_id"]: issue for issue in evidence_purity_issues(elements)}
    partition_by_id: dict[str, list[str]] = defaultdict(list)
    for issue in exclusive_partition_issues(elements):
        for element_id in issue.get("element_ids") or []:
            partition_by_id[str(element_id)].append(str(issue["code"]))
    for element in elements:
        issue = by_id.get(element.get("element_id"))
        invariant_reasons = sorted(set(partition_by_id.get(str(element.get("element_id")), [])))
        reasons = sorted(set((issue["reasons"] if issue else []) + invariant_reasons))
        element["evidence_purity"] = {
            "status": "FAIL" if reasons else "PASS",
            "contaminating_sibling_ids": issue["contaminating_sibling_ids"] if issue else [],
            "reasons": reasons,
        }


def repeated_control_cardinality_groups(observations: list[dict]) -> list[dict]:
    grouped: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for observation in observations:
        group_id = observation.get("repeated_control_group_id")
        control_type = observation.get("control_type")
        if group_id and control_type and observation.get("material") is True:
            grouped[(str(group_id), str(control_type))].append(observation)
    rows: list[dict] = []
    for (group_id, control_type), items in sorted(grouped.items()):
        represented = [item for item in items if item.get("match_status") == "REPRESENTED"]
        matched_ids = sorted({str(item.get("matched_element_id")) for item in represented if item.get("matched_element_id")})
        observed_count = len(items)
        represented_count = len(matched_ids)
        rows.append(
            {
                "group_id": group_id,
                "control_type": control_type,
                "observation_ids": [item.get("observation_id") for item in items],
                "observed_count": observed_count,
                "represented_count": represented_count,
                "matched_element_ids": matched_ids,
                "status": "PASS" if represented_count == observed_count else "MISMATCH",
            }
        )
    return rows
