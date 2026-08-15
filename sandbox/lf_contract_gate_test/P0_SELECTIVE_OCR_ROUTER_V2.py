#!/usr/bin/env python3
"""Fail-closed selective OCR routing contract for P0 visual evidence.

This module decides *when* a text observation may advance to a more expensive
or orthogonal OCR challenger. It does not perform OCR and does not contain
screen-, product-, coordinate-, or business-specific rules.

Required order:
  1. non-text / controls / QR / decoration are resolved structurally, not voted
     into text by OCR;
  2. independently proven pixel/geometry corrections may resolve the item;
  3. targeted Tesseract crop/re-read is attempted before an orthogonal model;
  4. Paddle is eligible only for a persistent machine-checkable invariant
     failure;
  5. valid-vs-valid disagreements and all unresolved cases abstain/review.

Confidence values are deliberately ignored: confidence is not comparable
across OCR engines and cannot authorize a correction.
"""
from __future__ import annotations

import re
from typing import Any

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
CURRENCY_RE = re.compile(r"^(?:S/|US\$|\$)\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})$")
DOCUMENT_RE = re.compile(r"^\d{8}$")
PHONE_RE = re.compile(r"^(?:\+51\s*)?\d{9}$")

NON_TEXT_CLASSES = {
    "NON_TEXT",
    "NON_TEXT_CONTROL",
    "NON_TEXT_QR",
    "NON_TEXT_ICON",
    "NON_TEXT_DECORATION",
}
STRUCTURAL_RESOLUTION_CODES = {
    "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
    "SEGMENTED_INPUT_CELL",
    "LAYOUT_RECONSTRUCTED",
    "CONTROL_STATE_FROM_PIXELS",
}


def normalize_text(value: Any) -> str:
    return " ".join(str(value or "").strip().casefold().split())


def validate_text(kind: str, value: Any) -> bool:
    text = str(value or "").strip()
    if not text:
        return False
    if kind == "email":
        return bool(EMAIL_RE.fullmatch(text))
    if kind == "currency":
        return bool(CURRENCY_RE.fullmatch(text))
    if kind == "document":
        return bool(DOCUMENT_RE.fullmatch(re.sub(r"^Ej\.\s*", "", text, flags=re.I)))
    if kind == "phone":
        compact = re.sub(r"[\s-]", "", re.sub(r"^Ej\.\s*", "", text, flags=re.I))
        return bool(PHONE_RE.fullmatch(compact))
    if kind in {"exact_text", "button_text", "generic_text"}:
        return bool(text)
    return False


def _stable_valid_targeted_attempts(observation: dict) -> list[dict]:
    kind = str(observation.get("kind") or "generic_text")
    output: list[dict] = []
    for attempt in observation.get("targeted_attempts") or []:
        if str(attempt.get("engine_family") or "TESSERACT") != "TESSERACT":
            continue
        if attempt.get("stable") is not True:
            continue
        text = str(attempt.get("text") or "").strip()
        valid = attempt.get("valid")
        if valid is None:
            valid = validate_text(kind, text)
        if valid is True:
            output.append({**attempt, "text": text, "valid": True})
    return output


def route_observation(observation: dict) -> dict:
    """Choose a fail-closed lane without using OCR confidence."""
    materiality = str(observation.get("materiality") or "TEXT")
    baseline_text = str(observation.get("baseline_text") or "").strip()
    kind = str(observation.get("kind") or "generic_text")
    baseline_valid = observation.get("baseline_valid")
    if baseline_valid is None:
        baseline_valid = validate_text(kind, baseline_text)

    if materiality in NON_TEXT_CLASSES:
        return {
            "decision": "DISCARD_NON_TEXT_OCR",
            "resolved": True,
            "invoke_paddle": False,
            "reason": "MATERIALITY_OR_CONTROL_PROVEN_OUTSIDE_OCR",
        }

    structural_code = str(observation.get("structural_resolution_code") or "")
    if observation.get("structural_resolution_proven") is True and structural_code in STRUCTURAL_RESOLUTION_CODES:
        return {
            "decision": "STRUCTURAL_PIXEL_RESOLVED",
            "resolved": True,
            "invoke_paddle": False,
            "reason": structural_code,
        }

    if observation.get("visible_truncated") is True:
        return {
            "decision": "VISIBLE_ONLY_NO_COMPLETION",
            "resolved": False,
            "invoke_paddle": False,
            "reason": "DO_NOT_COMPLETE_TEXT_BEYOND_VISIBLE_PIXELS",
        }

    targeted = _stable_valid_targeted_attempts(observation)
    if targeted:
        selected = targeted[0]
        candidate_text = selected["text"]
        if baseline_valid and normalize_text(candidate_text) != normalize_text(baseline_text):
            return {
                "decision": "NEEDS_REVIEW_VALID_DISAGREEMENT",
                "resolved": False,
                "invoke_paddle": False,
                "reason": "BASELINE_AND_TARGETED_TESSERACT_BOTH_VALID_BUT_DIFFER",
                "baseline_text": baseline_text,
                "targeted_text": candidate_text,
            }
        return {
            "decision": "TARGETED_TESSERACT_ACCEPT",
            "resolved": True,
            "invoke_paddle": False,
            "reason": "TARGETED_TESSERACT_REPAIRS_OR_CORROBORATES_MACHINE_INVARIANT",
            "text": candidate_text,
        }

    persistent_failure = observation.get("persistent_invariant_failure") is True
    if baseline_valid and not persistent_failure:
        return {
            "decision": "BASELINE_PRESERVED",
            "resolved": True,
            "invoke_paddle": False,
            "reason": "BASELINE_VALID_NO_MACHINE_FAILURE",
            "text": baseline_text,
        }

    if persistent_failure and observation.get("challenger_allowed") is True:
        return {
            "decision": "PADDLE_REQUIRED",
            "resolved": False,
            "invoke_paddle": True,
            "reason": "PERSISTENT_MACHINE_CHECKABLE_FAILURE_AFTER_TARGETED_TESSERACT",
        }

    return {
        "decision": "NEEDS_REVIEW",
        "resolved": False,
        "invoke_paddle": False,
        "reason": "NO_SAFE_MACHINE_RESOLUTION",
    }


def reconcile_paddle(observation: dict, paddle_text: Any, *, stable: bool, valid: bool | None = None) -> dict:
    """Reconcile a Paddle result only after route_observation authorized it."""
    route = route_observation(observation)
    if route["decision"] != "PADDLE_REQUIRED":
        return {
            "decision": "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION",
            "resolved": bool(route["resolved"]),
            "text": route.get("text"),
            "reason": route["reason"],
        }

    candidate = str(paddle_text or "").strip()
    kind = str(observation.get("kind") or "generic_text")
    if valid is None:
        valid = validate_text(kind, candidate)
    if not stable or not valid:
        return {
            "decision": "NEEDS_REVIEW",
            "resolved": False,
            "reason": "PADDLE_UNSTABLE_OR_MACHINE_INVALID",
        }

    baseline = str(observation.get("baseline_text") or "").strip()
    baseline_valid = observation.get("baseline_valid")
    if baseline_valid is None:
        baseline_valid = validate_text(kind, baseline)

    if baseline_valid:
        if normalize_text(baseline) == normalize_text(candidate):
            return {
                "decision": "EXACT_CROSS_FAMILY_AGREEMENT",
                "resolved": True,
                "text": baseline,
                "reason": "BOTH_FAMILIES_AGREE",
            }
        return {
            "decision": "BASELINE_PRESERVED_DISAGREEMENT",
            "resolved": False,
            "text": baseline,
            "reason": "BOTH_VALID_BUT_DIFFER",
        }

    return {
        "decision": "PADDLE_STRUCTURAL_CORRECTION",
        "resolved": True,
        "text": candidate,
        "reason": "CHALLENGER_REPAIRS_MACHINE_CHECKABLE_BASELINE_FAILURE",
    }
