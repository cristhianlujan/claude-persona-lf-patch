#!/usr/bin/env python3
"""Fail-closed selective OCR routing contract for P0 visual evidence.

V3 adds a profile-diversity guard before escalating punctuation-sensitive
machine-validated text (currently email) to an orthogonal OCR challenger.
The guard is screen/product agnostic: it reasons only about OCR-family metadata
already attached to targeted attempts.

Required order:
  1. resolve proven non-text/control/QR/decoration structurally;
  2. accept independently proven pixel/geometry corrections;
  3. attempt targeted Tesseract re-reads;
  4. for punctuation-sensitive kinds, require >=2 traceable Tesseract language
     profiles before concluding that same-family rereads are exhausted;
  5. allow Paddle only when a structured machine invariant remains unresolved;
  6. abstain/review every remaining ambiguity.

Caller-supplied confidence, validity, "stable", or "persistent failure" flags
are not authoritative. Validity and stability are recomputed inside this
contract. Confidence is deliberately ignored because values are not comparable
across OCR engines.
"""
from __future__ import annotations

import re
from collections import defaultdict
from typing import Any

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
CURRENCY_RE = re.compile(r"^(?:S/|US\$|\$)\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{2})$")
DOCUMENT_RE = re.compile(r"^\d{8}$")
PHONE_RE = re.compile(r"^(?:\+51)?\d{9}$")
CARD_NUMBER_RE = re.compile(r"^\d{16}$")

MACHINE_VALIDATED_KINDS = frozenset({"email", "currency", "document", "phone", "card_number"})
PROFILE_DIVERSITY_REQUIRED_KINDS = frozenset({"email"})
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
MIN_TRACEABLE_VARIANTS = 2
MIN_LANGUAGE_PROFILES_BEFORE_CHALLENGER = 2


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


def _traceable_attempts(attempts: Any, engine_family: str) -> list[dict]:
    """Return attempts with unique variant ids from one explicit OCR family."""
    output: list[dict] = []
    seen: set[str] = set()
    for attempt in attempts or []:
        if str(attempt.get("engine_family") or "") != engine_family:
            continue
        variant_id = str(attempt.get("variant_id") or "").strip()
        if not variant_id or variant_id in seen:
            continue
        seen.add(variant_id)
        output.append({
            "variant_id": variant_id,
            "text": str(attempt.get("text") or "").strip(),
            "language_profile": str(attempt.get("language_profile") or "").strip(),
        })
    return output


def _machine_valid_consensus(kind: str, attempts: Any, engine_family: str) -> dict | None:
    """Require >=2 distinct variants that independently yield the same valid text."""
    if not has_machine_validator(kind):
        return None
    valid_by_text: dict[str, list[dict]] = defaultdict(list)
    for attempt in _traceable_attempts(attempts, engine_family):
        if validate_text(kind, attempt["text"]):
            valid_by_text[normalize_text(attempt["text"])].append(attempt)
    winners = [group for group in valid_by_text.values() if len(group) >= MIN_TRACEABLE_VARIANTS]
    if len(winners) != 1:
        return None
    group = winners[0]
    return {
        "text": group[0]["text"],
        "variant_ids": [item["variant_id"] for item in group],
        "agreement_count": len(group),
    }


def _targeted_attempts(observation: dict) -> list[dict]:
    return _traceable_attempts(observation.get("targeted_attempts"), "TESSERACT")


def _targeted_attempt_count(observation: dict) -> int:
    return len(_targeted_attempts(observation))


def _tesseract_language_profile_count(observation: dict) -> int:
    return len({
        item["language_profile"]
        for item in _targeted_attempts(observation)
        if item["language_profile"]
    })


def route_observation(observation: dict) -> dict:
    """Choose a fail-closed lane without trusting declared validity/stability/confidence."""
    materiality = str(observation.get("materiality") or "TEXT")
    baseline_text = str(observation.get("baseline_text") or "").strip()
    kind = str(observation.get("kind") or "generic_text")
    machine_validated = has_machine_validator(kind)
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

    targeted_consensus = _machine_valid_consensus(kind, observation.get("targeted_attempts"), "TESSERACT")
    if targeted_consensus is not None:
        candidate_text = targeted_consensus["text"]
        if baseline_valid and normalize_text(candidate_text) != normalize_text(baseline_text):
            return {
                "decision": "NEEDS_REVIEW_VALID_DISAGREEMENT",
                "resolved": False,
                "invoke_paddle": False,
                "reason": "BASELINE_AND_TARGETED_TESSERACT_BOTH_MACHINE_VALID_BUT_DIFFER",
                "baseline_text": baseline_text,
                "targeted_text": candidate_text,
                "variant_ids": targeted_consensus["variant_ids"],
            }
        return {
            "decision": "TARGETED_TESSERACT_ACCEPT",
            "resolved": True,
            "invoke_paddle": False,
            "reason": "TWO_OR_MORE_TRACEABLE_TESSERACT_VARIANTS_REPAIR_OR_CORROBORATE_MACHINE_INVARIANT",
            "text": candidate_text,
            "variant_ids": targeted_consensus["variant_ids"],
        }

    if baseline_valid:
        return {
            "decision": "BASELINE_PRESERVED",
            "resolved": True,
            "invoke_paddle": False,
            "reason": "BASELINE_MACHINE_VALID_WITHOUT_CONTRADICTORY_VALID_TARGETED_CONSENSUS",
            "text": baseline_text,
        }

    targeted_count = _targeted_attempt_count(observation)
    if machine_validated and targeted_count >= MIN_TRACEABLE_VARIANTS and observation.get("challenger_allowed") is True:
        if (
            kind in PROFILE_DIVERSITY_REQUIRED_KINDS
            and _tesseract_language_profile_count(observation) < MIN_LANGUAGE_PROFILES_BEFORE_CHALLENGER
        ):
            return {
                "decision": "TESSERACT_PROFILE_EXPANSION_REQUIRED",
                "resolved": False,
                "invoke_paddle": False,
                "reason": "PUNCTUATION_SENSITIVE_KIND_NOT_YET_TESTED_ACROSS_TWO_TESSERACT_LANGUAGE_PROFILES",
                "targeted_attempt_count": targeted_count,
                "language_profile_count": _tesseract_language_profile_count(observation),
            }
        return {
            "decision": "PADDLE_REQUIRED",
            "resolved": False,
            "invoke_paddle": True,
            "reason": "MACHINE_INVALID_AFTER_TWO_OR_MORE_TRACEABLE_TARGETED_TESSERACT_VARIANTS",
            "targeted_attempt_count": targeted_count,
        }

    return {
        "decision": "NEEDS_REVIEW",
        "resolved": False,
        "invoke_paddle": False,
        "reason": "NO_SAFE_MACHINE_RESOLUTION",
        "targeted_attempt_count": targeted_count,
    }


def reconcile_paddle(observation: dict, paddle_attempts: Any) -> dict:
    """Reconcile Paddle only after routing authorization and repeated internal validation."""
    route = route_observation(observation)
    if route["decision"] != "PADDLE_REQUIRED":
        return {
            "decision": "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION",
            "resolved": bool(route["resolved"]),
            "text": route.get("text"),
            "reason": route["reason"],
        }

    kind = str(observation.get("kind") or "generic_text")
    consensus = _machine_valid_consensus(kind, paddle_attempts, "PADDLE")
    if consensus is None:
        return {
            "decision": "NEEDS_REVIEW",
            "resolved": False,
            "reason": "NO_STABLE_MACHINE_VALID_PADDLE_CONSENSUS",
        }

    candidate = consensus["text"]
    baseline = str(observation.get("baseline_text") or "").strip()
    baseline_valid = validate_text(kind, baseline)
    if baseline_valid:
        if normalize_text(baseline) == normalize_text(candidate):
            return {
                "decision": "EXACT_CROSS_FAMILY_AGREEMENT",
                "resolved": True,
                "text": baseline,
                "reason": "BOTH_FAMILIES_AGREE",
                "variant_ids": consensus["variant_ids"],
            }
        return {
            "decision": "BASELINE_PRESERVED_DISAGREEMENT",
            "resolved": False,
            "text": baseline,
            "reason": "BOTH_MACHINE_VALID_BUT_DIFFER",
            "variant_ids": consensus["variant_ids"],
        }

    return {
        "decision": "PADDLE_STRUCTURAL_CORRECTION",
        "resolved": True,
        "text": candidate,
        "reason": "REPEATED_CHALLENGER_CONSENSUS_REPAIRS_MACHINE_CHECKABLE_BASELINE_FAILURE",
        "variant_ids": consensus["variant_ids"],
    }
