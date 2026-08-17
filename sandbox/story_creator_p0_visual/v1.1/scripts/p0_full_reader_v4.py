#!/usr/bin/env python3
"""Canonical P0 V4 reader entrypoint with source-agnostic OCR root remediation.

This public module wraps the frozen implementation core and enforces three
general invariants before Human Review:

1. OCR ownership is split at source-derived geometric boundaries, including
   compact leading glyph/prefix tokens separated from adjacent field text.
2. Independent PSM readings may select the visible text by evidence consensus
   without silently increasing source confidence.
3. A disputed internal alphanumeric glyph may become punctuation only after two
   localized, traceable rereads of the same crop independently agree.

No screen literals, field names, product semantics or fixed source coordinates
are used by this module.
"""
from __future__ import annotations

import collections
import statistics
from difflib import SequenceMatcher
from typing import Any

import cv2

import p0_full_reader_v4_core as _core

for _name in dir(_core):
    if not _name.startswith("__"):
        globals().setdefault(_name, getattr(_core, _name))

_SAFE_REDETECTED_SYMBOLS = frozenset("@+:/._-")


def _compact_boundary_token(item: dict, median_height: float) -> bool:
    text = str(item.get("text") or "").strip()
    width = max(1, int(item.get("width", 0)))
    height = max(1, int(item.get("height", 0)))
    if not text or len(text) > 4 or width > 3.5 * height:
        return False
    has_symbol = any(not char.isalnum() for char in text)
    very_compact = width <= 1.55 * height and len(text) <= 2
    return has_symbol or very_compact


def segment_ocr_line_items(items: list[dict]) -> list[list[dict]]:
    """Split OCR tokens only when source geometry supports separate ownership."""
    if not items:
        return []
    ordered = sorted(items, key=lambda z: (int(z["x"]), int(z["y"])))
    median_height = float(statistics.median(max(1, int(z["height"])) for z in ordered))
    gap_limit = max(24.0, 2.25 * median_height)
    compact_gap_limit = max(12.0, 1.05 * median_height)
    groups: list[list[dict]] = [[ordered[0]]]

    for item in ordered[1:]:
        previous = groups[-1][-1]
        gap = int(item["x"]) - (int(previous["x"]) + int(previous["width"]))
        center_delta = abs(
            (int(item["y"]) + int(item["height"]) / 2)
            - (int(previous["y"]) + int(previous["height"]) / 2)
        )
        height_limit = 0.8 * max(int(item["height"]), int(previous["height"]), 1)
        item_text = str(item.get("text") or "").strip()

        compact_trailing_glyph = (
            len(item_text) == 1
            and int(item["height"]) <= 0.72 * max(1, int(previous["height"]))
            and gap >= 8
        )
        compact_leading_owner = (
            _compact_boundary_token(previous, median_height)
            and gap >= compact_gap_limit
        )
        strong_boundary = (
            gap > gap_limit
            or (gap > 12 and center_delta > height_limit)
            or compact_trailing_glyph
            or compact_leading_owner
        )
        if strong_boundary:
            groups.append([item])
        else:
            groups[-1].append(item)
    return groups


_core.segment_ocr_line_items = segment_ocr_line_items
ocr_lines = _core.ocr_lines


def _normalized(value: Any) -> str:
    return " ".join(str(value or "").casefold().split())


def _alnum_skeleton(value: Any) -> str:
    return "".join(char for char in str(value or "").casefold() if char.isalnum())


def _unique_winner(groups: dict[str, list[tuple[int, str]]], minimum: int = 2):
    eligible = [(key, value) for key, value in groups.items() if key and len(value) >= minimum]
    if not eligible:
        return None
    eligible.sort(key=lambda item: len(item[1]), reverse=True)
    if len(eligible) > 1 and len(eligible[0][1]) == len(eligible[1][1]):
        return None
    return eligible[0]


def resolve_ocr_consensus(variants: list[str]) -> dict[str, Any]:
    """Select a reading that is already present in independent OCR evidence."""
    observed = [(index, " ".join(str(value or "").split())) for index, value in enumerate(variants)]
    observed = [(index, value) for index, value in observed if value]
    if not observed:
        return {"text": "", "support": 0, "method": "NO_OBSERVATION", "indices": []}

    exact: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
    for pair in observed:
        exact[_normalized(pair[1])].append(pair)
    winner = _unique_winner(exact)
    if winner is not None:
        _, members = winner
        return {"text": members[0][1], "support": len(members), "method": "INDEPENDENT_PSM_EXACT", "indices": [index for index, _ in members]}

    skeletons: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
    for pair in observed:
        skeletons[_alnum_skeleton(pair[1])].append(pair)
    winner = _unique_winner(skeletons)
    if winner is not None:
        _, members = winner
        return {"text": members[0][1], "support": len(members), "method": "INDEPENDENT_PSM_ALNUM_EQUIVALENT", "indices": [index for index, _ in members]}

    return {"text": observed[0][1], "support": 1, "method": "NO_MAJORITY", "indices": [observed[0][0]]}


def _compact_for_symbol_compare(value: Any) -> str:
    return "".join(str(value or "").casefold().split())


def single_internal_symbol_replacement(reference: str, candidate: str):
    """Allow exactly one internal alnum->symbol change proven by reread."""
    left = _compact_for_symbol_compare(reference)
    right = _compact_for_symbol_compare(candidate)
    if not left or not right or left == right:
        return None
    matcher = SequenceMatcher(None, left, right, autojunk=False)
    edits = [opcode for opcode in matcher.get_opcodes() if opcode[0] != "equal"]
    if len(edits) != 1:
        return None
    tag, i1, i2, j1, j2 = edits[0]
    if tag != "replace" or i2 - i1 != 1 or j2 - j1 != 1:
        return None
    old, new = left[i1], right[j1]
    if not old.isalnum() or new not in _SAFE_REDETECTED_SYMBOLS:
        return None
    if j1 <= 0 or j1 >= len(right) - 1:
        return None
    if not right[j1 - 1].isalnum() or not right[j1 + 1].isalnum():
        return None
    return {"from": old, "to": new}


def _available_target_profile():
    try:
        languages = set(pytesseract.get_languages(config=""))
    except Exception:
        return None
    if {"spa", "eng"}.issubset(languages):
        return "spa+eng"
    return None


def _targeted_profile_attempts(image, region: dict) -> list[dict[str, Any]]:
    """Reread the existing crop only; never expand into sibling pixels."""
    if image is None or not hasattr(image, "shape") or len(getattr(image, "shape", ())) < 2:
        return []
    profile = _available_target_profile()
    if not profile:
        return []
    height, width = image.shape[:2]
    x1 = max(0, int(region.get("x", 0)))
    y1 = max(0, int(region.get("y", 0)))
    x2 = min(width, x1 + max(0, int(region.get("width", 0))))
    y2 = min(height, y1 + max(0, int(region.get("height", 0))))
    if x2 <= x1 or y2 <= y1:
        return []
    crop = image[y1:y2, x1:x2]
    if crop is None or not getattr(crop, "size", 0):
        return []
    attempts: list[dict[str, Any]] = []
    for psm in (7, 11):
        try:
            raw = pytesseract.image_to_string(crop, lang=profile, config=f"--psm {psm}")
        except Exception:
            continue
        text = " ".join(str(raw or "").split())
        if text:
            attempts.append({"engine_family": "TESSERACT", "language_profile": profile, "psm": psm, "variant_id": f"localized-{profile}-psm{psm}", "text": text})
    return attempts


def _targeted_consensus(attempts: list[dict[str, Any]]):
    by_text: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for attempt in attempts:
        text = str(attempt.get("text") or "").strip()
        variant_id = str(attempt.get("variant_id") or "").strip()
        if text and variant_id:
            by_text[_normalized(text)].append(attempt)
    winners = [members for members in by_text.values() if len({str(item["variant_id"]) for item in members}) >= 2]
    if len(winners) != 1:
        return None
    members = winners[0]
    return {"text": str(members[0]["text"]), "support": len({str(item["variant_id"]) for item in members}), "variant_ids": sorted({str(item["variant_id"]) for item in members})}


def _has_variant_disagreement(element: dict) -> bool:
    values = {_normalized(value) for value in element.get("ocr_variants") or [] if _normalized(value)}
    return len(values) >= 2


def _eligible_for_targeted_symbol_reread(element: dict) -> bool:
    if element.get("element_type") != "TEXT" or not element.get("visible_text"):
        return False
    if not _has_variant_disagreement(element):
        return False
    region = element.get("region") or {}
    width = int(region.get("width", 0))
    height = int(region.get("height", 0))
    alnum_len = len(_alnum_skeleton(element.get("visible_text")))
    if not (4 <= alnum_len and 1 <= height <= 80 and 1 <= width <= 600):
        return False
    return any(not char.isalnum() and not char.isspace() for char in str(element.get("visible_text") or ""))


def resolve_reader_output(candidate: dict, image, *, strict: bool) -> dict:
    """Apply evidence consensus and localized symbol redetection."""
    if not strict:
        return candidate
    consensus_selected: set[str] = set()
    independently_resolved: set[str] = set()
    for element in candidate.get("elements") or []:
        if element.get("element_type") != "TEXT" or not element.get("visible_text"):
            continue
        variants = [str(value or "") for value in element.get("ocr_variants") or []]
        resolution = resolve_ocr_consensus(variants)
        if int(resolution.get("support") or 0) >= 2 and resolution.get("text"):
            element["visible_text"] = resolution["text"]
            element["ocr_consensus_text"] = resolution["text"]
            element["ocr_consensus_support"] = int(resolution["support"])
            element["ocr_consensus_method"] = str(resolution["method"])
            element["ocr_consensus_variant_indices"] = list(resolution.get("indices") or [])
            element["ocr_agreement_count"] = int(resolution["support"])
            consensus_selected.add(str(element.get("element_id")))
            if resolution["method"] == "INDEPENDENT_PSM_EXACT" and float(element.get("confidence") or 0.0) >= 0.65:
                element["classification"] = "CONFIRMED"
                element["independent_redetection"] = True
                element["redetection_status"] = "CONSENSUS_REDETECTED"
                independently_resolved.add(str(element.get("element_id")))

        if not _eligible_for_targeted_symbol_reread(element):
            continue
        attempts = _targeted_profile_attempts(image, element.get("region") or {})
        element["targeted_ocr_attempts"] = attempts
        targeted = _targeted_consensus(attempts)
        if targeted is None:
            continue
        replacement = single_internal_symbol_replacement(str(element.get("visible_text") or ""), str(targeted["text"]))
        if replacement is None:
            continue
        element["visible_text"] = targeted["text"]
        element["ocr_consensus_text"] = targeted["text"]
        element["ocr_consensus_support"] = int(targeted["support"])
        element["ocr_consensus_method"] = "TARGETED_PROFILE_SINGLE_SYMBOL_REDETECTION"
        element["targeted_symbol_replacement"] = replacement
        element["targeted_ocr_variant_ids"] = list(targeted["variant_ids"])
        element["classification"] = "CONFIRMED"
        element["independent_redetection"] = True
        element["redetection_status"] = "PROFILE_REDETECTED"
        independently_resolved.add(str(element.get("element_id")))

    if independently_resolved:
        candidate["reader_uncertainties"] = [uncertainty for uncertainty in (candidate.get("reader_uncertainties") or []) if not (str(uncertainty.get("element_id")) in independently_resolved and str(uncertainty.get("code")) == "OCR_DISAGREEMENT")]

    raw = candidate.setdefault("raw_observations", {})
    raw["ocr_consensus_resolver"] = "EVIDENCE_WEIGHTED_PSM_V2"
    raw["ocr_geometric_partition"] = "ADAPTIVE_GAP_AND_COMPACT_PREFIX_V2"
    raw["targeted_symbol_redetection"] = "LOCALIZED_TESSERACT_SPA_ENG_PSM7_11_V1"
    raw["consensus_selected_count"] = len(consensus_selected)
    raw["independently_resolved_count"] = len(independently_resolved)
    return candidate


def _sync_core_overrides() -> None:
    for name in ("ocr_lines", "detect_compact_visuals", "grouping_signal", "cv_objects", "crop_evidence_ref", "crop_sha256", "annotate_evidence_purity", "pytesseract", "cv2"):
        if name in globals():
            setattr(_core, name, globals()[name])
    _core.segment_ocr_line_items = segment_ocr_line_items


def full_reader(source_path: str, ctx: dict) -> dict:
    """Canonical reader call with root OCR remediation applied before review."""
    _sync_core_overrides()
    candidate = _core.full_reader(source_path, ctx)
    strict = bool((ctx.get("remediation_state") or {}).get("strict_mode"))
    if not strict:
        return candidate
    try:
        image = cv2.imread(source_path)
    except Exception:
        image = None
    return resolve_reader_output(candidate, image, strict=True)
