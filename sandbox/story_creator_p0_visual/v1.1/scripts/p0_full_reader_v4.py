#!/usr/bin/env python3
"""P0 V4 reader compatibility surface with topology-invariant text grouping.

The previous production implementation is retained byte-for-byte in
`p0_full_reader_v4_legacy.py`. This module preserves the canonical import path,
re-exports the legacy surface, and replaces only OCR segment reconciliation.

The reconciliation is source-agnostic: it ignores Tesseract block/line topology
once segments exist, builds a geometric compatibility graph, and merges connected
components left-to-right. This removes greedy arrival-order and OCR-partition
sensitivity while preserving strong gap, baseline, overlap, and compact-nonword
guards. No screen literal, phrase literal, or fixed source coordinate is used.
"""
from __future__ import annotations

import p0_full_reader_v4_legacy as _legacy

for _name, _value in vars(_legacy).items():
    if not _name.startswith("__"):
        globals()[_name] = _value

_legacy_ocr_lines = _legacy.ocr_lines


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
    """Return topology-invariant OCR text groups from already detected segments."""
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
    legacy_segments = _legacy_ocr_lines(image, psm)
    return graph_reconcile_ocr_segments(legacy_segments)


_legacy.ocr_lines = ocr_lines


def full_reader(source_path: str, ctx: dict) -> dict:
    return _legacy.full_reader(source_path, ctx)
