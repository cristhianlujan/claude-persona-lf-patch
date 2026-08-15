#!/usr/bin/env python3
"""Mandatory pixel-first structured OCR router for PR166 remediation lot 05.

V5 preserves V4's OCR identity, mask-text and challenger rules but changes the
structured acceptance boundary: every machine-validated observation must carry
its source ROI pixels. The router itself derives deterministic visual evidence
before any machine-valid OCR text can be accepted.

This removes the opt-in evidence bypass and prevents forged/replayed evidence
from authorizing or blocking an unrelated observation.
"""
from __future__ import annotations

from typing import Any

import numpy as np

import P0_SELECTIVE_OCR_ROUTER_V4 as _v4
import P0_VISUAL_OBSCURATION_EVIDENCE_V2 as _visual

MACHINE_VALIDATED_KINDS = _v4.MACHINE_VALIDATED_KINDS
PROFILE_DIVERSITY_REQUIRED_KINDS = _v4.PROFILE_DIVERSITY_REQUIRED_KINDS
NON_TEXT_CLASSES = _v4.NON_TEXT_CLASSES
STRUCTURAL_RESOLUTION_CODES = _v4.STRUCTURAL_RESOLUTION_CODES
MIN_TRACEABLE_VARIANTS = _v4.MIN_TRACEABLE_VARIANTS
MIN_LANGUAGE_PROFILES_BEFORE_CHALLENGER = _v4.MIN_LANGUAGE_PROFILES_BEFORE_CHALLENGER
normalize_text = _v4.normalize_text
has_machine_validator = _v4.has_machine_validator
is_masked_structured_text = _v4.is_masked_structured_text
validate_text = _v4.validate_text

VISUAL_CONTRACT = "MANDATORY_PIXEL_DERIVED_OBSERVATION_BOUND_V2"


def _blocked(decision: str, reason: str) -> dict:
    return {
        "decision": decision,
        "resolved": False,
        "invoke_paddle": False,
        "reason": reason,
    }


def _structured_visual_preflight(observation: dict) -> tuple[dict | None, dict | None]:
    """Return (blocking_result, canonical_evidence).

    Non-machine-validated observations are outside this visual contract and
    return (None, None). Machine-validated observations fail closed if pixels or
    their binding are absent/invalid.
    """
    kind = str(observation.get("kind") or "generic_text").strip()
    if kind not in MACHINE_VALIDATED_KINDS:
        return None, None

    observation_id = str(observation.get("observation_id") or "").strip()
    source_sha = str(observation.get("source_sha256") or "").strip().lower()
    roi_xyxy = observation.get("roi_xyxy")
    gray = observation.get("source_roi_gray")

    if not observation_id or not source_sha or roi_xyxy is None or gray is None:
        return _blocked(
            "VISUAL_SOURCE_EVIDENCE_REQUIRED",
            "MACHINE_VALIDATED_STRUCTURED_TEXT_REQUIRES_SOURCE_ROI_PIXELS",
        ), None

    try:
        image = np.asarray(gray)
        evidence = _visual.analyze_visual_obscuration(
            image,
            observation_id=observation_id,
            kind=kind,
            source_sha256=source_sha,
            roi_xyxy=roi_xyxy,
        )
    except (TypeError, ValueError):
        return _blocked(
            "VISUAL_SOURCE_EVIDENCE_INVALID",
            "SOURCE_ROI_PIXELS_OR_BINDING_INVALID",
        ), None

    declared_roi_sha = str(observation.get("roi_sha256") or "").strip().lower()
    if declared_roi_sha and declared_roi_sha != evidence["roi_sha256"]:
        return _blocked(
            "VISUAL_ROI_SHA_MISMATCH",
            "DECLARED_ROI_SHA_DOES_NOT_MATCH_SOURCE_ROI_PIXELS",
        ), None

    supplied = observation.get("visual_obscuration_evidence")
    if supplied is not None and not _visual.verify_obscuration_evidence(
        supplied,
        image,
        observation_id=observation_id,
        kind=kind,
        source_sha256=source_sha,
        roi_xyxy=roi_xyxy,
    ):
        return _blocked(
            "VISUAL_EVIDENCE_BINDING_INVALID",
            "SUPPLIED_VISUAL_EVIDENCE_NOT_DERIVED_FROM_CURRENT_OBSERVATION_PIXELS",
        ), None

    if evidence.get("obscuration_risk_proven") is True:
        result = _blocked(
            "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH",
            "SOURCE_PIXELS_DO_NOT_SUPPORT_EXACT_STRUCTURED_TEXT",
        )
        result.update({
            "visual_evidence_sha256": evidence["evidence_sha256"],
            "visual_roi_sha256": evidence["roi_sha256"],
            "visual_detector": evidence["detector"],
        })
        return result, evidence

    return None, evidence


def _attach_visual_receipt(result: dict, evidence: dict | None) -> dict:
    output = dict(result)
    if evidence is not None:
        output.update({
            "visual_evidence_sha256": evidence["evidence_sha256"],
            "visual_roi_sha256": evidence["roi_sha256"],
            "visual_detector": evidence["detector"],
            "visual_obscuration_risk_proven": evidence["obscuration_risk_proven"],
        })
    return output


def _delegate_observation(observation: dict) -> dict:
    delegated = dict(observation)
    delegated.pop("source_roi_gray", None)
    # V4 consumes only its v1 evidence format. V5 has already recomputed and
    # validated the v2 evidence, so do not feed v2 into the legacy verifier.
    delegated.pop("visual_obscuration_evidence", None)
    return delegated


def route_observation(observation: dict) -> dict:
    blocking, evidence = _structured_visual_preflight(observation)
    if blocking is not None:
        return blocking
    result = _v4.route_observation(_delegate_observation(observation))
    return _attach_visual_receipt(result, evidence)


def reconcile_paddle(observation: dict, paddle_attempts: Any) -> dict:
    route = route_observation(observation)
    if route.get("decision") != "PADDLE_REQUIRED":
        return {
            "decision": "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION",
            "resolved": bool(route.get("resolved")),
            "text": route.get("text"),
            "reason": route.get("reason"),
            "visual_evidence_sha256": route.get("visual_evidence_sha256"),
            "visual_roi_sha256": route.get("visual_roi_sha256"),
            "visual_detector": route.get("visual_detector"),
        }

    # Visual preflight has already proved the current structured ROI does not
    # carry detector-level obscuration risk. V4 remains authoritative for
    # identity conflict, text-mask contamination and Paddle consensus.
    result = _v4.reconcile_paddle(_delegate_observation(observation), paddle_attempts)
    return _attach_visual_receipt(result, {
        "evidence_sha256": route["visual_evidence_sha256"],
        "roi_sha256": route["visual_roi_sha256"],
        "detector": route["visual_detector"],
        "obscuration_risk_proven": False,
    })
