#!/usr/bin/env python3
"""INV-1 visual-material conservation receipt.

This gate is deliberately fail-closed until a versioned corpus calibrates its
edge-energy threshold.  Producing a number from one screen is diagnostic, not
evidence that the threshold generalizes.
"""
from __future__ import annotations

import hashlib

import cv2
import numpy as np


ROOT_IDS = {"ROOT", "V4-ROOT"}
FULL_REGION_TYPES = {
    "TEXT",
    "LABEL",
    "HEADING",
    "LINK",
    "BUTTON_TEXT",
    "BADGE_TEXT",
    "INPUT_TEXT",
    "ICON",
    "ICON_OR_GLYPH",
    "CHECKBOX",
    "RADIO",
    "TOGGLE",
    "BRAND_MARK",
}
BOUNDARY_REGION_TYPES = {"CONTROL_REGION", "CONTAINER", "VISUAL_OBJECT", "IMAGE"}


def _file_sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _clip(region: dict, width: int, height: int, padding: int = 0) -> tuple[int, int, int, int]:
    x1 = max(0, int(region.get("x", 0)) - padding)
    y1 = max(0, int(region.get("y", 0)) - padding)
    x2 = min(width, int(region.get("x", 0)) + int(region.get("width", 0)) + padding)
    y2 = min(height, int(region.get("y", 0)) + int(region.get("height", 0)) + padding)
    return x1, y1, x2, y2


def _material_mask(image, candidate: dict) -> tuple[np.ndarray, list[dict]]:
    height, width = image.shape[:2]
    mask = np.zeros((height, width), dtype=np.uint8)
    justifications: list[dict] = []
    for element in candidate.get("elements") or []:
        if element.get("element_id") in ROOT_IDS:
            continue
        region = element.get("crop_region") or element.get("region") or {}
        element_type = str(element.get("element_type") or "")
        x1, y1, x2, y2 = _clip(region, width, height, padding=3)
        if x2 <= x1 or y2 <= y1:
            continue
        if element_type in FULL_REGION_TYPES:
            mask[y1:y2, x1:x2] = 255
            mode = "ATOMIC_REGION"
        elif element_type in BOUNDARY_REGION_TYPES:
            # Large containers may explain their own border, never every edge
            # inside them. Otherwise one page-sized box would hide omissions.
            thickness = max(3, min(8, round(min(x2 - x1, y2 - y1) * 0.08)))
            cv2.rectangle(mask, (x1, y1), (x2 - 1, y2 - 1), 255, thickness)
            mode = "BOUNDARY_ONLY"
        else:
            continue
        justifications.append(
            {
                "element_id": element.get("element_id"),
                "element_type": element_type,
                "coverage_mode": mode,
                "region": {"x": x1, "y": y1, "width": x2 - x1, "height": y2 - y1},
            }
        )
    return mask, justifications


def _components(residual: np.ndarray, source_sha256: str, *, minimum_edge_pixels: int) -> list[dict]:
    count, _labels, stats, _centroids = cv2.connectedComponentsWithStats((residual > 0).astype(np.uint8), 8)
    rows: list[dict] = []
    for label in range(1, count):
        x, y, width, height, edge_pixels = (int(value) for value in stats[label])
        if edge_pixels < minimum_edge_pixels or width * height < 16:
            continue
        seed = f"{source_sha256}:{x}:{y}:{width}:{height}:{edge_pixels}".encode()
        rows.append(
            {
                "residual_id": "RES-" + hashlib.sha256(seed).hexdigest()[:16],
                "region": {"x": x, "y": y, "width": width, "height": height},
                "edge_pixels": edge_pixels,
                "status": "UNEXPLAINED",
                "evidence_ref": "p0://v4/residual/" + hashlib.sha256(seed).hexdigest(),
            }
        )
    rows.sort(key=lambda row: row["edge_pixels"], reverse=True)
    return rows


def run_visual_residual_gate(
    source_path: str,
    expected_source_sha256: str,
    candidate: dict,
    *,
    execution_id: str,
    loop_version: str,
    calibration: dict | None = None,
) -> dict:
    actual_sha256 = _file_sha256(source_path)
    if actual_sha256 != expected_source_sha256:
        return {
            "schema_version": "p0-visual-residual-v4/v1",
            "execution_id": execution_id,
            "loop_version": loop_version,
            "source_sha256": actual_sha256,
            "status": "BLOCKED",
            "errors": ["SOURCE_SHA256_MISMATCH"],
            "findings": [],
        }
    image = cv2.imread(source_path)
    if image is None:
        return {
            "schema_version": "p0-visual-residual-v4/v1",
            "execution_id": execution_id,
            "loop_version": loop_version,
            "source_sha256": actual_sha256,
            "status": "ERROR",
            "errors": ["SOURCE_DECODE_FAILED"],
            "findings": [],
        }

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edge_map = cv2.Canny(gray, 70, 180)
    material_mask, justifications = _material_mask(image, candidate)
    residual = cv2.bitwise_and(edge_map, cv2.bitwise_not(material_mask))
    total_edge_pixels = int(np.count_nonzero(edge_map))
    residual_edge_pixels = int(np.count_nonzero(residual))
    minimum_edge_pixels = int((calibration or {}).get("minimum_component_edge_pixels", 12))
    components = _components(residual, actual_sha256, minimum_edge_pixels=minimum_edge_pixels)

    calibration = dict(calibration or {})
    corpus_size = int(calibration.get("corpus_size", 0) or 0)
    corpus_sha256 = calibration.get("corpus_sha256")
    threshold = calibration.get("maximum_residual_edge_ratio")
    calibrated = corpus_size >= 10 and bool(corpus_sha256) and isinstance(threshold, (int, float))
    ratio = residual_edge_pixels / max(1, total_edge_pixels)
    if not calibrated:
        status = "BLOCKED_UNCALIBRATED"
        errors = ["RESIDUAL_THRESHOLD_REQUIRES_VERSIONED_CORPUS_F01"]
    elif components and ratio > float(threshold):
        status = "BLOCKED"
        errors = ["UNEXPLAINED_VISUAL_RESIDUAL"]
    else:
        status = "PASS"
        errors = []

    return {
        "schema_version": "p0-visual-residual-v4/v1",
        "execution_id": execution_id,
        "loop_version": loop_version,
        "source_sha256": actual_sha256,
        "status": status,
        "calibrated": calibrated,
        "calibration": {
            "corpus_size": corpus_size,
            "corpus_sha256": corpus_sha256,
            "maximum_residual_edge_ratio": threshold,
            "minimum_component_edge_pixels": minimum_edge_pixels,
        },
        "edge_energy": {
            "total_edge_pixels": total_edge_pixels,
            "represented_edge_pixels": total_edge_pixels - residual_edge_pixels,
            "residual_edge_pixels": residual_edge_pixels,
            "residual_edge_ratio": round(ratio, 8),
        },
        "justifications": justifications,
        "findings": [
            {"category": "UNEXPLAINED_VISUAL_RESIDUAL", "severity": "HIGH", **component}
            for component in components
        ],
        "errors": errors,
    }
