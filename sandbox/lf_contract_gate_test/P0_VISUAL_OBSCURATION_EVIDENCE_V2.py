#!/usr/bin/env python3
"""Deterministic pixel-derived obscuration evidence for structured OCR values.

V2 addresses PR166 independent-audit findings:
- evidence is recomputable from the actual ROI pixels, not merely self-sealed;
- evidence is bound to observation identity + kind + source + ROI;
- detector thresholds are scale-relative rather than fixed pixel ceilings;
- both dark-on-light and light-on-dark polarities are evaluated;
- repeated compact filled components require surrounding text-like context so
  standalone UI controls/icons are not promoted to obscuration evidence;
- touching filled runs are treated as obscuration risk without reconstructing
  hidden content.

The detector is intentionally a negative safety signal. It never identifies the
hidden value or names a mask glyph.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
from collections import deque
from typing import Any

import numpy as np

SCHEMA_VERSION = "p0-visual-obscuration-risk/v2"
DETECTOR_ID = "PIXEL_DERIVED_CONTEXTUAL_FILLED_RUN_V2"
MIN_REPEATED_COMPONENTS = 3
_HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


def _canonical_bytes(payload: dict) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _seal(payload: dict) -> dict:
    result = dict(payload)
    result["evidence_sha256"] = hashlib.sha256(_canonical_bytes(payload)).hexdigest()
    return result


def _otsu_threshold(gray: np.ndarray) -> int:
    hist = np.bincount(gray.reshape(-1), minlength=256).astype(np.float64)
    total = float(gray.size)
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
            crop = foreground[y0:y1 + 1, x0:x1 + 1].copy()
            output.append({
                "x": x0,
                "y": y0,
                "w": box_w,
                "h": box_h,
                "area": area,
                "fill": area / float(box_w * box_h),
                "cx": (x0 + x1) / 2.0,
                "cy": (y0 + y1) / 2.0,
                "crop": crop,
            })
    return output


def _erode8(mask: np.ndarray) -> np.ndarray:
    image = np.asarray(mask, dtype=bool)
    height, width = image.shape
    padded = np.pad(image, 1, constant_values=False)
    output = np.ones((height, width), dtype=bool)
    for dy in range(3):
        for dx in range(3):
            output &= padded[dy:dy + height, dx:dx + width]
    return output


def _core_thickness_ratio(crop: np.ndarray) -> float:
    current = np.asarray(crop, dtype=bool)
    if not current.any():
        return 0.0
    steps = 0
    while True:
        next_mask = _erode8(current)
        if not next_mask.any():
            break
        steps += 1
        current = next_mask
        if steps > 64:
            break
    return (steps + 1) / float(max(1, min(crop.shape)))


def _component_key(item: dict) -> tuple[int, int, int, int, int]:
    return (int(item["x"]), int(item["y"]), int(item["w"]), int(item["h"]), int(item["area"]))


def _compact_filled_candidates(components: list[dict], roi_height: int) -> list[dict]:
    min_dim = max(2, int(math.ceil(0.10 * roi_height)))
    max_dim = max(min_dim, int(math.floor(0.80 * roi_height)))
    candidates: list[dict] = []
    for item in components:
        w = int(item["w"])
        h = int(item["h"])
        area = int(item["area"])
        fill = float(item["fill"])
        if area < 4 or w < min_dim or h < min_dim:
            continue
        if w > max_dim or h > max_dim:
            continue
        aspect = w / float(h)
        if aspect < 0.60 or aspect > 1.67:
            continue
        if fill < 0.55:
            continue
        core_ratio = _core_thickness_ratio(item["crop"])
        if core_ratio < 0.30:
            continue
        candidate = dict(item)
        candidate["core_ratio"] = core_ratio
        candidates.append(candidate)
    return sorted(candidates, key=lambda item: (item["x"], item["y"]))


def _similar_component(left: dict, right: dict) -> bool:
    max_h = max(float(left["h"]), float(right["h"]))
    if abs(float(left["cy"]) - float(right["cy"])) > max(2.0, 0.35 * max_h):
        return False

    def ratio(a: float, b: float) -> float:
        lo = max(min(a, b), 1.0)
        return max(a, b) / lo

    if ratio(float(left["w"]), float(right["w"])) > 1.35:
        return False
    if ratio(float(left["h"]), float(right["h"])) > 1.35:
        return False
    if ratio(float(left["area"]), float(right["area"])) > 1.50:
        return False
    gap = int(right["x"]) - (int(left["x"]) + int(left["w"]))
    if gap < 0:
        return False
    if gap > 2.5 * max(int(left["w"]), int(right["w"])):
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


def _compound_filled_runs(components: list[dict], roi_height: int) -> list[dict]:
    min_dim = max(2, int(math.ceil(0.10 * roi_height)))
    max_h = max(min_dim, int(math.floor(0.80 * roi_height)))
    output: list[dict] = []
    for item in components:
        w = int(item["w"])
        h = int(item["h"])
        if h < min_dim or h > max_h:
            continue
        aspect = w / float(max(h, 1))
        if aspect < 2.40 or aspect > 8.0:
            continue
        if float(item["fill"]) < 0.72:
            continue
        core_ratio = _core_thickness_ratio(item["crop"])
        if core_ratio < 0.28:
            continue
        estimated_repeats = int(round(aspect))
        if estimated_repeats < MIN_REPEATED_COMPONENTS:
            continue
        candidate = dict(item)
        candidate["core_ratio"] = core_ratio
        candidate["estimated_repeats"] = estimated_repeats
        output.append(candidate)
    return output


def _text_like_context_count(components: list[dict], excluded: list[dict], roi_height: int, roi_width: int) -> int:
    excluded_keys = {_component_key(item) for item in excluded}
    count = 0
    min_height = max(3, int(math.ceil(0.22 * roi_height)))
    for item in components:
        if _component_key(item) in excluded_keys:
            continue
        h = int(item["h"])
        w = int(item["w"])
        if h < min_height or h > 0.95 * roi_height:
            continue
        if w > 0.90 * roi_width:
            continue
        count += 1
    return count


def _analyze_polarity(foreground: np.ndarray, polarity: str) -> dict:
    height, width = foreground.shape
    components = _components(foreground)
    repeated_candidates = _compact_filled_candidates(components, height)
    compound_runs = _compound_filled_runs(components, height)
    repeated_run = _max_repeated_run(repeated_candidates)
    context_count = _text_like_context_count(
        components,
        [*repeated_candidates, *compound_runs],
        height,
        width,
    )
    risk = context_count >= 2 and (
        repeated_run >= MIN_REPEATED_COMPONENTS
        or any(int(item["estimated_repeats"]) >= MIN_REPEATED_COMPONENTS for item in compound_runs)
    )
    return {
        "polarity": polarity,
        "component_count": len(components),
        "candidate_component_count": len(repeated_candidates),
        "max_repeated_component_run": repeated_run,
        "compound_filled_run_count": len(compound_runs),
        "max_compound_estimated_repeats": max(
            [int(item["estimated_repeats"]) for item in compound_runs],
            default=0,
        ),
        "text_like_context_count": context_count,
        "obscuration_risk": bool(risk),
    }


def analyze_visual_obscuration(
    gray: np.ndarray,
    *,
    observation_id: str,
    kind: str,
    source_sha256: str,
    roi_xyxy: list[int] | tuple[int, int, int, int],
) -> dict:
    """Derive deterministic, observation-bound evidence directly from pixels."""
    image = np.asarray(gray)
    if image.ndim != 2 or image.dtype != np.uint8 or image.size == 0:
        raise ValueError("gray must be a non-empty uint8 2D array")
    obs_id = str(observation_id or "").strip()
    if not obs_id:
        raise ValueError("observation_id is required")
    structured_kind = str(kind or "").strip()
    if not structured_kind:
        raise ValueError("kind is required")
    source_sha = str(source_sha256 or "").strip().lower()
    if not _HEX64_RE.fullmatch(source_sha):
        raise ValueError("source_sha256 must be lowercase 64-hex")
    coords = [int(value) for value in roi_xyxy]
    if len(coords) != 4 or coords[2] <= coords[0] or coords[3] <= coords[1]:
        raise ValueError("roi_xyxy must be [x1,y1,x2,y2] with positive area")
    if (coords[2] - coords[0], coords[3] - coords[1]) != (image.shape[1], image.shape[0]):
        raise ValueError("roi dimensions must match gray image dimensions")

    threshold = _otsu_threshold(image)
    analyses = [
        _analyze_polarity(image <= threshold, "DARK_ON_LIGHT"),
        _analyze_polarity(image > threshold, "LIGHT_ON_DARK"),
    ]
    positive = [item for item in analyses if item["obscuration_risk"]]
    selected = max(
        analyses,
        key=lambda item: (
            int(item["obscuration_risk"]),
            int(item["max_repeated_component_run"]),
            int(item["max_compound_estimated_repeats"]),
            int(item["candidate_component_count"]),
        ),
    )
    roi_sha = hashlib.sha256(image.tobytes(order="C")).hexdigest()
    payload = {
        "schema_version": SCHEMA_VERSION,
        "detector": DETECTOR_ID,
        "observation_id": obs_id,
        "kind": structured_kind,
        "source_sha256": source_sha,
        "roi_sha256": roi_sha,
        "roi_xyxy": coords,
        "threshold": threshold,
        "selected_polarity": selected["polarity"],
        "candidate_component_count": int(selected["candidate_component_count"]),
        "max_repeated_component_run": int(selected["max_repeated_component_run"]),
        "compound_filled_run_count": int(selected["compound_filled_run_count"]),
        "max_compound_estimated_repeats": int(selected["max_compound_estimated_repeats"]),
        "text_like_context_count": int(selected["text_like_context_count"]),
        "obscuration_risk_proven": bool(positive),
        "exact_text_reconstruction_authorized": False,
    }
    return _seal(payload)


def verify_obscuration_evidence(
    evidence: Any,
    gray: np.ndarray,
    *,
    observation_id: Any,
    kind: Any,
    source_sha256: Any,
    roi_xyxy: Any,
) -> bool:
    """Recompute from pixels and require byte-semantic equality with evidence.

    A caller cannot turn a negative result into a positive one by editing fields
    and recalculating the digest: the verifier derives the canonical evidence
    again from the supplied ROI bytes and exact observation binding.
    """
    if not isinstance(evidence, dict):
        return False
    try:
        recomputed = analyze_visual_obscuration(
            np.asarray(gray),
            observation_id=str(observation_id or ""),
            kind=str(kind or ""),
            source_sha256=str(source_sha256 or ""),
            roi_xyxy=roi_xyxy,
        )
    except (TypeError, ValueError):
        return False
    return evidence == recomputed
