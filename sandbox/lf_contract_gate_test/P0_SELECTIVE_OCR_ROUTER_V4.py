#!/usr/bin/env python3
"""Fail-closed extension for visibly masked structured OCR values.

V4 preserves the V3 selective OCR contract and adds general invariants:
structured values containing strong obscuration evidence must never be promoted
as exact machine truth or sent to a challenger to reconstruct hidden content;
and a stable variant_id may not silently identify contradictory payloads.

This is screen/product agnostic. It only reasons over traceable OCR evidence.

Orden de evaluación en route_observation (CAMBIO DE CONTRATO RESPECTO DE V3):

  1. conflicto global de identidad variant_id       <-- ARC-014/AUD-027
  2. conflicto intra-Tesseract de identidad/profile
  3. evidencia de máscara en valor estructurado     <-- AUD-026 carrier-safe
  4. materialidad no-textual
  5. resolución estructural probada por píxeles
  6. truncamiento visible
  7. consenso Tesseract dirigido
  8. baseline machine-valid
  9. carril challenger / abstención

El guard de máscara conserva precedencia sobre materialidad no-textual y
resolución estructural porque esos metadatos son suministrados por el caller.
La evidencia de máscara se inspecciona sobre TODOS los attempts de la familia,
incluso cuando variant_id está vacío: identidad ausente impide consenso, pero
no puede borrar evidencia material. Un stable variant_id se interpreta además
como identidad global de evidencia; payloads textuales distintos no pueden
coexistir bajo ese ID aunque provengan de familias OCR distintas.

AUD-03 permanece como limitación explícita: sólo U+2022 y runs OCR de >=3 '*'
son marcadores de máscara empíricamente respaldados. Glifos adicionales no se
reclasifican sin evidencia source-bound independiente.
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
MASK_SCOPE_LIMITATION = "AUD-03_UNSUPPORTED_MASK_GLYPHS_REQUIRE_SOURCE_BOUND_EVIDENCE"


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


def _raw_family_attempts(attempts: Any, engine_family: str | None = None) -> list[dict]:
    """Return raw family evidence without requiring a stable variant identity.

    Missing/blank variant_id makes an attempt ineligible for identity-based
    consensus, but its text can still carry blocking evidence such as a visible
    mask. This separation closes AUD-026 without granting untraceable attempts
    positive consensus credit.
    """
    output: list[dict] = []
    for attempt in attempts or []:
        family = str(attempt.get("engine_family") or "").strip()
        if engine_family is not None and family != engine_family:
            continue
        output.append({
            "engine_family": family,
            "variant_id": str(attempt.get("variant_id") or "").strip(),
            "text": str(attempt.get("text") or "").strip(),
            "language_profile": str(attempt.get("language_profile") or "").strip(),
        })
    return output


def _raw_traceable_attempts(attempts: Any, engine_family: str) -> list[dict]:
    """Return traceable attempts from one family without deduplicating IDs."""
    return [
        item
        for item in _raw_family_attempts(attempts, engine_family)
        if item["variant_id"]
    ]


def _attempt_payload(item: dict, include_profile: bool = True) -> tuple[str, ...]:
    """Canonical material payload for identity-consistency checks.

    Within one OCR family, language profile is material because profile identity
    participates in diversity gates. Across OCR families, profile namespaces are
    not comparable; global identity conflict therefore compares normalized text
    while family-local validation still checks profile consistency.
    """
    text = str(item.get("text") or "").strip()
    if include_profile:
        return (text, str(item.get("language_profile") or "").strip())
    return (text,)


def _has_variant_id_conflict(attempts: Any, engine_family: str | None = None) -> bool:
    """Detect one stable ID bound to materially different payloads.

    Identical duplicates are benign and may later coalesce. Conflicting
    duplicates fail closed; no first-wins/last-wins semantics are allowed.
    If engine_family is None, identity is checked across the full evidence
    universe using text as the cross-family comparable payload.
    """
    payload_by_id: dict[str, tuple[str, ...]] = {}
    if engine_family is None:
        universe = [item for item in _raw_family_attempts(attempts) if item["variant_id"]]
        include_profile = False
    else:
        universe = _raw_traceable_attempts(attempts, engine_family)
        include_profile = True

    for item in universe:
        variant_id = item["variant_id"]
        payload = _attempt_payload(item, include_profile=include_profile)
        previous = payload_by_id.get(variant_id)
        if previous is None:
            payload_by_id[variant_id] = payload
            continue
        if previous != payload:
            return True
    return False


def _variant_conflict_result(engine_family: str) -> dict:
    return {
        "decision": "EVIDENCE_VARIANT_ID_CONFLICT",
        "resolved": False,
        "invoke_paddle": False,
        "reason": "CONFLICTING_PAYLOADS_SHARE_VARIANT_ID",
        "engine_family": engine_family,
    }


def _raw_attempt_texts(attempts: Any, engine_family: str | None = None) -> list[str]:
    """Return non-empty texts without using identity as an evidence filter."""
    return [
        item["text"]
        for item in _raw_family_attempts(attempts, engine_family)
        if item["text"]
    ]


def _traceable_targeted_texts(observation: dict) -> list[str]:
    """Compatibility helper: traceable Tesseract texts, pre-deduplication."""
    return [
        item["text"]
        for item in _raw_traceable_attempts(observation.get("targeted_attempts"), "TESSERACT")
        if item["text"]
    ]


def _has_structured_mask_evidence(observation: dict) -> bool:
    kind = str(observation.get("kind") or "generic_text")
    if kind not in MACHINE_VALIDATED_KINDS:
        return False
    candidates = [
        str(observation.get("baseline_text") or "").strip(),
        *_raw_attempt_texts(observation.get("targeted_attempts")),
    ]
    return any(is_masked_structured_text(text) for text in candidates if text)


def route_observation(observation: dict) -> dict:
    """Block global identity conflict, local provenance conflict, then mask."""
    attempts = observation.get("targeted_attempts")
    if _has_variant_id_conflict(attempts, None):
        return _variant_conflict_result("MULTI_FAMILY")
    if _has_variant_id_conflict(attempts, "TESSERACT"):
        return _variant_conflict_result("TESSERACT")
    if _has_structured_mask_evidence(observation):
        return {
            "decision": "VISIBLE_MASKED_NO_COMPLETION",
            "resolved": False,
            "invoke_paddle": False,
            "reason": "STRUCTURED_VALUE_CONTAINS_OBSCURATION_MARKERS",
        }
    return _v3.route_observation(observation)


def _machine_valid_consensus(kind: str, attempts: Any, engine_family: str) -> dict | None:
    """Recompute consensus with V4's hardened validator and identity guard.

    Reimplemented deliberately: the equivalent helper in V3 resolves its own
    module-level validator, so delegating there would bypass V4's mask guard.
    """
    if not has_machine_validator(kind):
        return None
    if _has_variant_id_conflict(attempts, engine_family):
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
    """Return True when any raw Paddle attempt carries mask evidence.

    Identity is intentionally not a prerequisite for blocking evidence.
    """
    if kind not in MACHINE_VALIDATED_KINDS:
        return False
    return any(
        is_masked_structured_text(text)
        for text in _raw_attempt_texts(attempts, "PADDLE")
    )


def reconcile_paddle(observation: dict, paddle_attempts: Any) -> dict:
    """Never allow an orthogonal OCR engine to reconstruct hidden content.

    Challenger identity conflict is evaluated after confirming PADDLE_REQUIRED
    and before mask evidence or consensus. Stable IDs are global across the
    observation + challenger evidence universe; missing IDs still carry blocking
    mask evidence but cannot create identity conflicts or positive consensus.
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
    combined_attempts = [*(observation.get("targeted_attempts") or []), *(paddle_attempts or [])]

    if _has_variant_id_conflict(combined_attempts, None):
        return _variant_conflict_result("MULTI_FAMILY")

    if _has_variant_id_conflict(paddle_attempts, "PADDLE"):
        return _variant_conflict_result("PADDLE")

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
