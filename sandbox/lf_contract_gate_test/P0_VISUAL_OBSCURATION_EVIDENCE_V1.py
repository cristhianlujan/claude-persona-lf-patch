#!/usr/bin/env python3
"""Source-bound visual obscuration-risk evidence for structured OCR values.

This module deliberately does *not* infer masks from OCR glyphs. It inspects the
source ROI and emits a conservative fail-closed signal when pixels contain a
run of repeated compact filled components consistent with obscuration. The
signal means exact textual truth is unsafe; it does not claim the hidden value
or a specific mask character.

Evidence is bound to source SHA, ROI SHA and ROI coordinates and sealed with a
canonical digest so callers cannot mutate the claim without invalidating it.
The detector is screen/product agnostic and uses only grayscale geometry.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import deque
from typing import Any

import numpy as np

SCHEMA_VERSION = "p0-visual-obscuration-risk/v1"
DETECTOR_ID = "REPEATED_COMPACT_FILLED_COMPONENTS_V1"
MIN_REPEATED_COMPONENTS = 3
_HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


def _canonical_bytes(payload: dict) -> bytes:
    return json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def _seal(payload: dict) -> dict:
    sealed = dict(payload)
    sealed["evidence_sha256"] = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    return sealed


def _otsu_threshold(gray: np.ndarray) -> int:
    hist = np.bincount(gray.reshape(-1), minlength=256).astype(np.float64)
    total = float(gray.size)
    if total <= 0:
        return 127
    weighted_sum = float(np.dot(np.arange(256, dtype=np.float64), hist))
    weight_bg = 0.0
    sum_bg = 0.0
    best_variance = -1.0
    best_threshold = 127
    for level in range(256):
        count = hist[level]
        weight_bg += count
        if weight_bg <= 0.0:
            continue
        weight_fg = total - weight_bg
        if weight_fg <= 0.0:
            break
        sum_bg += level * count
        mean_bg = sum_bg / weight_bg
        mean_fg = (weighted_sum - sum_bg) / weight_fg
        between = weight_bg * weight_fg * (mean_bg - mean_fg) ** 2
        if between > best_variance:
            best_variance = between
            best_threshold = level
    return int(best_threshold)


def _components(foreground: np.ndarray) -> list[dict]:
    height, width = foreground.shape
    visited = np.zeros_like(foreground, dtype=np.uint8)
    output: list[dict] = []
    neighbors = (
        (-1, -1), (-1, 0), (-1, 1),
        (0, -1),           (0, 1),
        (1, -1),  (1, 0),  (1, 1),
    )

    for y in range(height):
        for x in range(width):
            if not foreground[y, x] or visited[y, x]:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[y, x] = 1
            xs: list[int] = []
            ys: list[int] = []
            while queue:
                cx, cy = queue.popleft()
                xs.append(cx)
                ys.append(cy)
                for dy, dx in neighbors:
                    nx = cx + dx
                    ny = cy + dy
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    if foreground[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = 1
                        queue.append((nx, ny))
            x0, x1 = min(xs), max(xs)
            y0, y1 = min(ys), max(ys)
            box_w = x1 - x0 + 1
            box_h = y1 - y0 + 1
            area = len(xs)
            output.append({
                "x": x0,
                "y": y0,
                "w": box_w,
                "h": box_h,
                "area": area,
                "fill": area / float(box_w * box_h),
                "cx": (x0 + x1) / 2.0,
                "cy": (y0 + y1) / 2.0,
            })
    return output


def _compact_filled_candidates(components: list[dict]) -> list[dict]:
    candidates: list[dict] = []
    for item in components:
        w = int(item["w"])
        h = int(item["h"])
        area = int(item["area"])
        fill = float(item["fill"])
        if area < 3 or w < 2 or h < 2:
            continue
        if w > 20 or h > 20:
            continue
        aspect = w / float(h)
        if aspect < 0.45 or aspect > 2.20:
            continue
        if fill < 0.45:
            continue
        candidates.append(item)
    return sorted(candidates, key=lambda item: (item["x"], item["y"]))


def _similar_component(left: dict, right: dict) -> bool:
    max_h = max(float(left["h"]), float(right["h"]))
    if abs(float(left["cy"]) - float(right["cy"])) > max(2.0, 0.45 * max_h):
        return False

    def ratio(a: float, b: float) -> float:
        lo = max(min(a, b), 1.0)
        return max(a, b) / lo

    if ratio(float(left["w"]), float(right["w"])) > 1.60:
        return False
    if ratio(float(left["h"]), float(right["h"])) > 1.60:
        return False
    if ratio(float(left["area"]), float(right["area"])) > 1.85:
        return False
    gap = int(right["x"]) - (int(left["x"]) + int(left["w"]))
    if gap < 0:
        return False
    if gap > max(12, 3 * max(int(left["w"]), int(right["w"]))):
        return False
    return True


def _max_repeated_run(candidates: list[dict]) -> int:
    if not candidates:
        return 0
    best = 1
    run = 1
    for left, right in zip(candidates, candidates[1:]):
        if _similar_component(left, right):
            run += 1
            best = max(best, run)
        else:
            run = 1
    return best


def analyze_visual_obscuration(
    gray: np.ndarray,
    *,
    source_sha256: str,
    roi_xyxy: list[int] | tuple[int, int, int, int],
) -> dict:
    """Return sealed visual evidence without reconstructing hidden content.

    A positive result is an *obscuration risk* gate: repeated compact filled
    components make exact structured text unsafe. It is intentionally weaker
    than saying that the components are certainly a password mask.
    """
    image = np.asarray(gray)
    if image.ndim != 2 or image.dtype != np.uint8 or image.size == 0:
        raise ValueError("gray must be a non-empty uint8 2D array")
    source_sha = str(source_sha256 or "").strip().lower()
    if not _HEX64_RE.fullmatch(source_sha):
        raise ValueError("source_sha256 must be lowercase 64-hex")
    coords = [int(value) for value in roi_xyxy]
    if len(coords) != 4 or coords[2] <= coords[0] or coords[3] <= coords[1]:
        raise ValueError("roi_xyxy must be [x1,y1,x2,y2] with positive area")
    if (coords[2] - coords[0], coords[3] - coords[1]) != (image.shape[1], image.shape[0]):
        raise ValueError("roi dimensions must match gray image dimensions")

    threshold = _otsu_threshold(image)
    foreground = image <= threshold
    components = _components(foreground)
    candidates = _compact_filled_candidates(components)
    repeated = _max_repeated_run(candidates)
    roi_sha = hashlib.sha256(image.tobytes(order="C")).hexdigest()
    payload = {
        "schema_version": SCHEMA_VERSION,
        "detector": DETECTOR_ID,
        "source_sha256": source_sha,
        "roi_sha256": roi_sha,
        "roi_xyxy": coords,
        "threshold": threshold,
        "candidate_component_count": len(candidates),
        "max_repeated_component_run": repeated,
        "obscuration_risk_proven": repeated >= MIN_REPEATED_COMPONENTS,
        "exact_text_reconstruction_authorized": False,
    }
    return _seal(payload)


def verify_obscuration_evidence(
    evidence: Any,
    *,
    source_sha256: Any,
    roi_sha256: Any,
    roi_xyxy: Any,
) -> bool:
    """Validate canonical evidence and bind it to the current observation."""
    if not isinstance(evidence, dict):
        return False
    supplied_digest = str(evidence.get("evidence_sha256") or "").strip().lower()
    if not _HEX64_RE.fullmatch(supplied_digest):
        return False
    payload = {key: value for key, value in evidence.items() if key != "evidence_sha256"}
    expected_digest = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    if supplied_digest != expected_digest:
        return False
    if payload.get("schema_version") != SCHEMA_VERSION or payload.get("detector") != DETECTOR_ID:
        return False
    if payload.get("obscuration_risk_proven") is not True:
        return False
    if payload.get("exact_text_reconstruction_authorized") is not False:
        return False
    if int(payload.get("max_repeated_component_run") or 0) < MIN_REPEATED_COMPONENTS:
        return False

    source_sha = str(source_sha256 or "").strip().lower()
    roi_sha = str(roi_sha256 or "").strip().lower()
    try:
        coords = [int(value) for value in roi_xyxy]
    except Exception:
        return False
    if not _HEX64_RE.fullmatch(source_sha) or not _HEX64_RE.fullmatch(roi_sha):
        return False
    if payload.get("source_sha256") != source_sha:
        return False
    if payload.get("roi_sha256") != roi_sha:
        return False
    if payload.get("roi_xyxy") != coords:
        return False
    return True
