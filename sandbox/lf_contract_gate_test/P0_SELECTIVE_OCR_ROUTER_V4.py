#!/usr/bin/env python3
"""Fail-closed extension for visibly masked structured OCR values.

V4 preserves the V3 selective OCR contract and adds one general invariant:
structured values containing strong obscuration evidence must never be promoted
as exact machine truth or sent to a challenger to reconstruct hidden content.

This is screen/product agnostic. It only reasons over the visible/OCR text.

Orden de evaluación en route_observation (CAMBIO DE CONTRATO RESPECTO DE V3):

  1. evidencia de máscara en valor estructurado   <-- NUEVO, precede a todo
  2. materialidad no-textual
  3. resolución estructural probada por píxeles
  4. truncamiento visible
  5. consenso Tesseract dirigido
  6. baseline machine-valid
  7. carril challenger / abstención

El guard de máscara precede deliberadamente a (2) y (3) porque
'structural_resolution_proven' y 'materiality' son metadatos suministrados
por el caller. Bajo el contrato vigente la metadata del caller no puede
producir verdad por sí misma, y la obscuración es observable directamente
en el texto. Consecuencia declarada: una observación enmascarada de tipo
estructurado deja de resolverse como DISCARD_NON_TEXT_OCR o
STRUCTURAL_PIXEL_RESOLVED y pasa a VISIBLE_MASKED_NO_COMPLETION.
"""
from __future__ import annotations

import re
from collections import defaultdict
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


def _machine_valid_consensus(kind: str, attempts: Any, engine_family: str) -> dict | None:
    """Recompute consensus with V4's hardened validator.

    Reimplemented deliberately: the equivalent helper in V3 resolves its own
    module-level validator, so delegating there would bypass V4's mask guard.
    """
    if not has_machine_validator(kind):
        return None
    valid_by_text: dict[str, list[dict]] = defaultdict(list)
    for attempt in _v3._traceable_attempts(attempts, engine_family):
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


def _challenger_mask_evidence(kind: str, attempts: Any) -> bool:
    """Return True when any traceable Paddle attempt carries mask evidence."""
    if kind not in MACHINE_VALIDATED_KINDS:
        return False
    return any(
        is_masked_structured_text(item["text"])
        for item in _v3._traceable_attempts(attempts, "PADDLE")
    )


def reconcile_paddle(observation: dict, paddle_attempts: Any) -> dict:
    """Never allow an orthogonal OCR engine to reconstruct hidden content.

    Challenger mask evidence is evaluated after confirming PADDLE_REQUIRED and
    before any machine-valid consensus is computed.
    """
    route = route_observation(observation)
    if route["decision"] != "PADDLE_REQUIRED":
        return {
            "decision": "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION",
            "resolved": bool(route["resolved"]),
            "text": route.get("text"),
            "reason": route["reason"],
        }

    kind = str(observation.get("kind") or "generic_text")

    # A masked challenger attempt contaminates the entire challenger batch.
    # Filtering it out and promoting clean-looking siblings could invent the
    # content that the pixels deliberately obscured.
    if _challenger_mask_evidence(kind, paddle_attempts):
        return {
            "decision": "PADDLE_MASKED_NO_COMPLETION",
            "resolved": False,
            "invoke_paddle": False,
            "reason": "CHALLENGER_OUTPUT_CONTAINS_OBSCURATION_MARKERS",
        }

    consensus = _machine_valid_consensus(kind, paddle_attempts, "PADDLE")
    if consensus is None:
        return {
            "decision": "NEEDS_REVIEW",
            "resolved": False,
            "reason": "NO_STABLE_MACHINE_VALID_PADDLE_CONSENSUS",
        }

    candidate = consensus["text"]
    baseline = str(observation.get("baseline_text") or "").strip()
    if validate_text(kind, baseline):
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
