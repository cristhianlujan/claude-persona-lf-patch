#!/usr/bin/env python3
"""Local-geometry visual obscuration evidence for structured OCR values.

V3 keeps V2's source/observation binding and recomputation guarantees, while
moving the safety decision from ROI-global geometry to local component geometry.
It emits three states:

CLEAR
OBSCURATION_RISK
AMBIGUOUS_VISUAL_EVIDENCE

The detector never reconstructs hidden content and never uses screen IDs,
expected text, product IDs, or source hashes as expected-value logic.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
from collections import deque
from typing import Any

import numpy as np

SCHEMA_VERSION = "p0-visual-obscuration-risk/v3"
DETECTOR_ID = "PIXEL_DERIVED_LOCAL_INLINE_OBSERVABILITY_V3"
STATE_CLEAR = "CLEAR"
STATE_RISK = "OBSCURATION_RISK"
STATE_AMBIGUOUS = "AMBIGUOUS_VISUAL_EVIDENCE"
STATE_RANK = {STATE_CLEAR: 0, STATE_AMBIGUOUS: 1, STATE_RISK: 2}
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


def _local_scale(components: list[dict]) -> float:
    """Estimate text/component scale from local foreground, independent of ROI padding."""
    heights = np.asarray(
        [float(item["h"]) for item in components if int(item["area"]) >= 2],
        dtype=np.float64,
    )
    if heights.size == 0:
        return 1.0
    lower = float(np.quantile(heights, 0.25))
    upper = float(np.quantile(heights, 0.90))
    core = heights[(heights >= max(2.0, lower)) & (heights <= max(lower, upper))]
    if core.size == 0:
        core = heights
    return max(1.0, float(np.median(core)))


def _compact_filled_candidates(components: list[dict], local_scale: float) -> list[dict]:
    candidates: list[dict] = []
    min_h = max(2.0, 0.18 * local_scale)
    max_h = max(min_h, 2.70 * local_scale)
    min_w = max(2.0, 0.16 * local_scale)
    max_w = max(min_w, 3.00 * local_scale)
    for item in components:
        w = float(item["w"])
        h = float(item["h"])
        if int(item["area"]) < 4 or h < min_h or h > max_h or w < min_w or w > max_w:
            continue
        aspect = w / max(h, 1.0)
        if aspect < 0.55 or aspect > 1.80:
            continue
        if float(item["fill"]) < 0.52:
            continue
        core_ratio = _core_thickness_ratio(item["crop"])
        if core_ratio < 0.26:
            continue
        candidate = dict(item)
        candidate["core_ratio"] = core_ratio
        candidates.append(candidate)
    return sorted(candidates, key=lambda item: (int(item["x"]), int(item["y"])))


def _similar_component(left: dict, right: dict, local_scale: float) -> bool:
    local_h = max(local_scale, float(left["h"]), float(right["h"]))
    if abs(float(left["cy"]) - float(right["cy"])) > max(2.0, 0.35 * local_h):
        return False

    def ratio(a: float, b: float) -> float:
        lo = max(min(a, b), 1.0)
        return max(a, b) / lo

    if ratio(float(left["w"]), float(right["w"])) > 1.60:
        return False
    if ratio(float(left["h"]), float(right["h"])) > 1.60:
        return False
    if ratio(float(left["area"]), float(right["area"])) > 1.80:
        return False
    gap = int(right["x"]) - (int(left["x"]) + int(left["w"]))
    if gap < 0:
        return False
    if gap > max(3.0, 2.50 * max(int(left["w"]), int(right["w"])), 0.80 * local_scale):
        return False
    return True


def _candidate_runs(candidates: list[dict], local_scale: float) -> list[list[dict]]:
    if not candidates:
        return []
    output: list[list[dict]] = []
    current = [candidates[0]]
    for item in candidates[1:]:
        if _similar_component(current[-1], item, local_scale):
            current.append(item)
        else:
            output.append(current)
            current = [item]
    output.append(current)
    return output


def _compound_filled_runs(components: list[dict], local_scale: float) -> list[dict]:
    output: list[dict] = []
    min_h = max(2.0, 0.18 * local_scale)
    max_h = max(min_h, 2.70 * local_scale)
    for item in components:
        w = float(item["w"])
        h = float(item["h"])
        if int(item["area"]) < 8 or h < min_h or h > max_h:
            continue
        aspect = w / max(h, 1.0)
        if aspect < 1.70 or aspect > 10.0:
            continue
        if float(item["fill"]) < 0.60:
            continue
        core_ratio = _core_thickness_ratio(item["crop"])
        if core_ratio < 0.22:
            continue
        candidate = dict(item)
        candidate["core_ratio"] = core_ratio
        candidate["estimated_repeats"] = max(2, int(round(aspect)))
        output.append(candidate)
    return output


def _inline_context(components: list[dict], run: list[dict], local_scale: float) -> dict:
    excluded_keys = {_component_key(item) for item in run}
    x0 = min(int(item["x"]) for item in run)
    x1 = max(int(item["x"]) + int(item["w"]) - 1 for item in run)
    center_y = float(np.median([float(item["cy"]) for item in run]))
    run_h = float(np.median([float(item["h"]) for item in run]))
    baseline_band = 1.25 * max(local_scale, run_h)
    horizontal_reach = 6.00 * max(local_scale, min(run_h, 2.0 * local_scale))
    left_count = 0
    right_count = 0
    left_gap = float("inf")
    right_gap = float("inf")
    for item in components:
        if _component_key(item) in excluded_keys:
            continue
        h = float(item["h"])
        context_scale = max(local_scale, run_h)
        if h < max(2.0, 0.20 * min(local_scale, context_scale)) or h > 6.00 * context_scale:
            continue
        if abs(float(item["cy"]) - center_y) > baseline_band:
            continue
        item_x0 = int(item["x"])
        item_x1 = int(item["x"]) + int(item["w"]) - 1
        if item_x1 < x0:
            gap = float(x0 - item_x1)
            if gap <= horizontal_reach:
                left_count += 1
                left_gap = min(left_gap, gap)
        elif item_x0 > x1:
            gap = float(item_x0 - x1)
            if gap <= horizontal_reach:
                right_count += 1
                right_gap = min(right_gap, gap)
    return {
        "left_count": left_count,
        "right_count": right_count,
        "left_gap": None if math.isinf(left_gap) else left_gap,
        "right_gap": None if math.isinf(right_gap) else right_gap,
        "run_height": run_h,
    }


def _classify_run(run: list[dict], context: dict, local_scale: float) -> tuple[str, str]:
    count = len(run)
    left = int(context["left_count"])
    right = int(context["right_count"])
    bilateral = left > 0 and right > 0
    if count >= 2 and bilateral:
        return STATE_RISK, "BILATERAL_INLINE_REPEATED"
    single_h = float(np.median([float(item["h"]) for item in run]))
    single_w = float(np.median([float(item["w"]) for item in run]))
    if (
        count == 1
        and bilateral
        and single_h >= max(2.0, 0.35 * local_scale)
        and single_w >= max(2.0, 0.30 * local_scale)
    ):
        return STATE_AMBIGUOUS, "BILATERAL_INLINE_SINGLE"

    # One-sided groups are only ambiguous when they are tightly attached to a
    # same-line carrier. This avoids turning nearby pagination/control groups
    # into material structured-text blockers.
    run_h = float(context["run_height"])
    close_limit = 0.55 * max(local_scale, run_h)
    left_gap = context["left_gap"]
    right_gap = context["right_gap"]
    tightly_one_sided = (
        (left > 0 and right == 0 and left_gap is not None and float(left_gap) <= close_limit)
        or (right > 0 and left == 0 and right_gap is not None and float(right_gap) <= close_limit)
    )
    if count >= 2 and tightly_one_sided:
        return STATE_AMBIGUOUS, "ONE_SIDED_TIGHT_REPEATED"
    return STATE_CLEAR, "NO_INLINE_CARRIER"


def _analyze_polarity(foreground: np.ndarray, polarity: str) -> dict:
    occupancy = float(np.mean(foreground))
    # The inverse/background polarity forms one giant field on ordinary text.
    # Rejecting implausibly dense foreground prevents background complements
    # from creating false compact runs while still supporting dark mode.
    if occupancy < 0.001 or occupancy > 0.45:
        return {
            "polarity": polarity,
            "foreground_occupancy": occupancy,
            "component_count": 0,
            "candidate_component_count": 0,
            "max_repeated_component_run": 0,
            "compound_filled_run_count": 0,
            "max_compound_estimated_repeats": 0,
            "local_scale_px": 0.0,
            "visual_state": STATE_CLEAR,
            "context_mode": "IMPLAUSIBLE_FOREGROUND_OCCUPANCY",
        }

    components = _components(foreground)
    local_scale = _local_scale(components)
    candidates = _compact_filled_candidates(components, local_scale)
    runs = _candidate_runs(candidates, local_scale)
    compound_runs = _compound_filled_runs(components, local_scale)

    best_state = STATE_CLEAR
    best_mode = "NONE"
    best_run = 0

    for run in runs:
        context = _inline_context(components, run, local_scale)
        state, mode = _classify_run(run, context, local_scale)
        if (STATE_RANK[state], len(run)) > (STATE_RANK[best_state], best_run):
            best_state = state
            best_mode = mode
            best_run = len(run)

    for item in compound_runs:
        context = _inline_context(components, [item], local_scale)
        repeats = int(item["estimated_repeats"])
        left = int(context["left_count"])
        right = int(context["right_count"])
        if left > 0 and right > 0:
            state = STATE_RISK
            mode = "BILATERAL_INLINE_COMPOUND"
        else:
            run_h = float(context["run_height"])
            close_limit = 0.55 * max(local_scale, run_h)
            left_gap = context["left_gap"]
            right_gap = context["right_gap"]
            tight = (
                (left > 0 and right == 0 and left_gap is not None and float(left_gap) <= close_limit)
                or (right > 0 and left == 0 and right_gap is not None and float(right_gap) <= close_limit)
            )
            state = STATE_AMBIGUOUS if tight else STATE_CLEAR
            mode = "ONE_SIDED_TIGHT_COMPOUND" if tight else "NO_INLINE_CARRIER"
        if (STATE_RANK[state], repeats) > (STATE_RANK[best_state], best_run):
            best_state = state
            best_mode = mode
            best_run = repeats

    return {
        "polarity": polarity,
        "foreground_occupancy": occupancy,
        "component_count": len(components),
        "candidate_component_count": len(candidates),
        "max_repeated_component_run": max([len(run) for run in runs], default=0),
        "compound_filled_run_count": len(compound_runs),
        "max_compound_estimated_repeats": max(
            [int(item["estimated_repeats"]) for item in compound_runs],
            default=0,
        ),
        "local_scale_px": local_scale,
        "visual_state": best_state,
        "context_mode": best_mode,
    }


def analyze_visual_obscuration(
    gray: np.ndarray,
    *,
    observation_id: str,
    kind: str,
    source_sha256: str,
    roi_xyxy: list[int] | tuple[int, int, int, int],
) -> dict:
    """Derive deterministic, observation-bound local visual evidence."""
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
    selected = max(
        analyses,
        key=lambda item: (
            STATE_RANK[str(item["visual_state"])],
            int(item["max_repeated_component_run"]),
            int(item["max_compound_estimated_repeats"]),
            int(item["candidate_component_count"]),
            -float(item["foreground_occupancy"]),
        ),
    )
    visual_state = str(selected["visual_state"])
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
        "foreground_occupancy": float(selected["foreground_occupancy"]),
        "local_scale_px": float(selected["local_scale_px"]),
        "candidate_component_count": int(selected["candidate_component_count"]),
        "max_repeated_component_run": int(selected["max_repeated_component_run"]),
        "compound_filled_run_count": int(selected["compound_filled_run_count"]),
        "max_compound_estimated_repeats": int(selected["max_compound_estimated_repeats"]),
        "context_mode": str(selected["context_mode"]),
        "visual_state": visual_state,
        "obscuration_risk_proven": visual_state == STATE_RISK,
        "ambiguous_visual_evidence": visual_state == STATE_AMBIGUOUS,
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
    """Recompute from pixels and require byte-semantic equality with evidence."""
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
