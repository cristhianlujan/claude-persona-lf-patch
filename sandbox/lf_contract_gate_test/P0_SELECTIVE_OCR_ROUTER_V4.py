#!/usr/bin/env python3
"""Fail-closed extension for visibly masked structured OCR values.

V4 preserves the V3 selective OCR contract and adds one general invariant:
structured values containing strong obscuration evidence must never be promoted
as exact machine truth or sent to a challenger to reconstruct hidden content.

This is screen/product agnostic. It only reasons over the visible/OCR text.
"""
from __future__ import annotations

import re
from typing import Any

import P0_SELECTIVE_OCR_ROUTER_V3 as _v3

MACHINE_VALIDATED_KINDS = _v3.MACHINE_VALIDATED_KINDS
PROFILE_DIVERSITY_REQUIRED_KINDS = _v3.PROFILE_DIVERSITY_REQUIRED_KINDS
NON_TEXT_CLASSES = _v3.NON_TEXT_CLASSES
STRUCTURAL_RESOLUTION_CODES = _v3.STRUCTURAL_RESOLUTION_CODES
MIN_TRACEABLE_VARIANTS = _v3.MIN_TRACEABLE_VARIANTS
MIN_LANGUAGE_PROFILES_BEFORE_CHALLENGER = _v3.MIN_LANGUAGE_PROFILES_BEFORE_CHALLENGER
normalize_text = _v3.normalize_text
has_machine_validator = _v3.has_machine_validator

# The real source visibly contains U+2022 bullets and Tesseract reproducibly
# renders that obscuration as a run of >=3 asterisks. Do not generalize to
# merely similar glyphs without independent evidence. A single '*' remains
# allowed so legitimate local-parts are not globally rejected.
VISIBLE_BULLET_MASK_RE = re.compile(r"•")
REPEATED_STAR_MASK_RE = re.compile(r"\*{3,}")


def is_masked_structured_text(value: Any) -> bool:
    text = str(value or "").strip()
    if not text:
        return False
    return bool(VISIBLE_BULLET_MASK_RE.search(text) or REPEATED_STAR_MASK_RE.search(text))


def validate_text(kind: str, value: Any) -> bool:
    """Reject obscured structured values before delegating syntax validation."""
    if kind in MACHINE_VALIDATED_KINDS and is_masked_structured_text(value):
        return False
    return _v3.validate_text(kind, value)


def _traceable_targeted_texts(observation: dict) -> list[str]:
    output: list[str] = []
    seen: set[str] = set()
    for attempt in observation.get("targeted_attempts") or []:
        if str(attempt.get("engine_family") or "") != "TESSERACT":
            continue
        variant_id = str(attempt.get("variant_id") or "").strip()
        if not variant_id or variant_id in seen:
            continue
        seen.add(variant_id)
        text = str(attempt.get("text") or "").strip()
        if text:
            output.append(text)
    return output


def _has_structured_mask_evidence(observation: dict) -> bool:
    kind = str(observation.get("kind") or "generic_text")
    if kind not in MACHINE_VALIDATED_KINDS:
        return False
    candidates = [str(observation.get("baseline_text") or "").strip(), *_traceable_targeted_texts(observation)]
    return any(is_masked_structured_text(text) for text in candidates if text)


def route_observation(observation: dict) -> dict:
    """Block exact-resolution/challenger lanes when obscuration is observable."""
    if _has_structured_mask_evidence(observation):
        return {
            "decision": "VISIBLE_MASKED_NO_COMPLETION",
            "resolved": False,
            "invoke_paddle": False,
            "reason": "STRUCTURED_VALUE_CONTAINS_OBSCURATION_MARKERS",
        }
    return _v3.route_observation(observation)


def reconcile_paddle(observation: dict, paddle_attempts: Any) -> dict:
    """Never let an orthogonal OCR engine reconstruct visibly hidden content."""
    route = route_observation(observation)
    if route["decision"] != "PADDLE_REQUIRED":
        return {
            "decision": "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION",
            "resolved": bool(route["resolved"]),
            "text": route.get("text"),
            "reason": route["reason"],
        }
    return _v3.reconcile_paddle(observation, paddle_attempts)
