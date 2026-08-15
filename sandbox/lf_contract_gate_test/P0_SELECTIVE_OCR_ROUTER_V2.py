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

Caller-supplied confidence or validity flags are never authoritative. Machine
validity is recomputed inside this contract. Confidence is deliberately ignored:
it is not comparable across OCR engines and cannot authorize a correction.
"""
from __future__ import annotations

import re
from typing import Any

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
CURRENCY_RE = re.compile(r"^(?:S/|US\$|\$)\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{2})$")
DOCUMENT_RE = re.compile(r"^\d{8}$")
PHONE_RE = re.compile(r"^(?:\+51)?\d{9}$")
CARD_NUMBER_RE = re.compile(r"^\d{16}$")

MACHINE_VALIDATED_KINDS = frozenset({"email", "currency", "document", "phone", "card_number"})
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


def has_machine_validator(kind: str) -> bool:
    return kind in MACHINE_VALIDATED_KINDS


def validate_text(kind: str, value: Any) -> bool:
    """Recompute objective syntax validity. Unstructured text is never self-validating."""
    text = str(value or "").strip()
    if not text:
        return False
    if kind == "email":
        return bool(EMAIL_RE.fullmatch(text))
    if kind == "currency":
        return bool(CURRENCY_RE.fullmatch(text))
    if kind == "document":
        compact = re.sub(r"^Ej\.\s*", "", text, flags=re.I).strip()
        return bool(DOCUMENT_RE.fullmatch(compact))
    if kind == "phone":
        compact = re.sub(r"^Ej\.\s*", "", text, flags=re.I)
        compact = re.sub(r"[\s()-]", "", compact)
        return bool(PHONE_RE.fullmatch(compact))
    if kind == "card_number":
        compact = re.sub(r"[\s-]", "", text)
        return bool(CARD_NUMBER_RE.fullmatch(compact))
    return False


def _stable_machine_valid_targeted_attempts(observation: dict) -> list[dict]:
    kind = str(observation.get("kind") or "generic_text")
    if not has_machine_validator(kind):
        return []
    output: list[dict] = []
    for attempt in observation.get("targeted_attempts") or []:
        if str(attempt.get("engine_family") or "TESSERACT") != "TESSERACT":
            continue
        if attempt.get("stable") is not True:
            continue
        text = str(attempt.get("text") or "").strip()
        # Deliberately ignore attempt['valid'] and any confidence supplied by caller.
        if validate_text(kind, text):
            output.append({"engine_family": "TESSERACT", "text": text, "stable": True})
    return output


def route_observation(observation: dict) -> dict:
    """Choose a fail-closed lane without using OCR confidence or declared validity."""
    materiality = str(observation.get("materiality") or "TEXT")
    baseline_text = str(observation.get("baseline_text") or "").strip()
    kind = str(observation.get("kind") or "generic_text")
    machine_validated = has_machine_validator(kind)
    # Deliberately ignore observation['baseline_valid']; recompute internally.
    baseline_valid = validate_text(kind, baseline_text) if machine_validated else False

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

    targeted = _stable_machine_valid_targeted_attempts(observation)
    if targeted:
        candidate_text = targeted[0]["text"]
        if baseline_valid and normalize_text(candidate_text) != normalize_text(baseline_text):
            return {
                "decision": "NEEDS_REVIEW_VALID_DISAGREEMENT",
                "resolved": False,
                "invoke_paddle": False,
                "reason": "BASELINE_AND_TARGETED_TESSERACT_BOTH_MACHINE_VALID_BUT_DIFFER",
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
            "reason": "BASELINE_MACHINE_VALID_NO_MACHINE_FAILURE",
            "text": baseline_text,
        }

    if persistent_failure and observation.get("challenger_allowed") is True and machine_validated:
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


def reconcile_paddle(observation: dict, paddle_text: Any, *, stable: bool) -> dict:
    """Reconcile Paddle only after authorization and internal machine validation."""
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
    # Never trust caller-supplied valid/confidence flags; recompute here.
    candidate_valid = validate_text(kind, candidate)
    if not stable or not candidate_valid:
        return {
            "decision": "NEEDS_REVIEW",
            "resolved": False,
            "reason": "PADDLE_UNSTABLE_OR_MACHINE_INVALID",
        }

    baseline = str(observation.get("baseline_text") or "").strip()
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
            "reason": "BOTH_MACHINE_VALID_BUT_DIFFER",
        }

    return {
        "decision": "PADDLE_STRUCTURAL_CORRECTION",
        "resolved": True,
        "text": candidate,
        "reason": "CHALLENGER_REPAIRS_MACHINE_CHECKABLE_BASELINE_FAILURE",
    }
