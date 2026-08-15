#!/usr/bin/env python3
"""Regression for glyph-independent, source-bound visual obscuration safety.

AUD-03 cannot be closed by enumerating OCR strings such as XXX, ###, blocks or
Unicode lookalikes: the same text can be literal. V8 instead proves a stronger
invariant: when source pixels carry sealed obscuration-risk evidence, no OCR
glyph rendering may be promoted as exact structured truth.

The evidence detector is pixel/geometry based, source/ROI bound and independent
of screen, product, expected text and OCR engine. Without visual evidence,
unsupported glyphs are not silently reclassified as masks; the router remains
conservative rather than inventing semantics from text alone.
"""
from __future__ import annotations

import copy
import hashlib
import json

import numpy as np

import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V7 as v7
import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V6 as v6
import P0_SELECTIVE_OCR_ROUTER_V4 as router
import P0_VISUAL_OBSCURATION_EVIDENCE_V1 as visual


def t_attempt(variant_id: str, text: str, profile: str) -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": profile,
    }


def observation_for(text: str, evidence: dict | None, *, source_sha: str, roi_sha: str, roi_xyxy: list[int]) -> dict:
    result = {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": text,
        "targeted_attempts": [
            t_attempt("v1", text, "eng"),
            t_attempt("v2", text, "spa"),
        ],
        "challenger_allowed": True,
        "source_sha256": source_sha,
        "roi_sha256": roi_sha,
        "roi_xyxy": roi_xyxy,
    }
    if evidence is not None:
        result["visual_obscuration_evidence"] = evidence
    return result


def _draw_filled_square_run() -> np.ndarray:
    image = np.full((24, 96), 255, dtype=np.uint8)
    for x in (28, 40, 52):
        image[9:15, x:x + 6] = 0
    return image


def _draw_cross_run() -> np.ndarray:
    image = np.full((24, 96), 255, dtype=np.uint8)
    for x0 in (24, 40, 56):
        for offset in range(7):
            image[8 + offset, x0 + offset] = 0
            image[8 + offset, x0 + 6 - offset] = 0
    return image


def main() -> int:
    if v7.main() != 0:
        raise SystemExit("FAIL_V7_PREREQUISITE")

    checks: dict[str, bool] = {}
    fixture, fixture_roi_sha = v6.load_fixture()
    fixture_evidence = visual.analyze_visual_obscuration(
        fixture,
        source_sha256=v6.GOVERNED_SOURCE_SHA256,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    )

    checks["real_fixture_visual_risk_detected"] = fixture_evidence.get("obscuration_risk_proven") is True
    checks["real_fixture_detector_roi_sha_exact"] = fixture_evidence.get("roi_sha256") == fixture_roi_sha
    checks["real_fixture_evidence_binding_valid"] = visual.verify_obscuration_evidence(
        fixture_evidence,
        source_sha256=v6.GOVERNED_SOURCE_SHA256,
        roi_sha256=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    )

    # Independent synthetic positive proves the detector property is not tied to
    # the governed screen coordinates or expected text.
    synthetic = _draw_filled_square_run()
    synthetic_source_sha = hashlib.sha256(b"synthetic-source-v8").hexdigest()
    synthetic_roi = [17, 31, 17 + synthetic.shape[1], 31 + synthetic.shape[0]]
    synthetic_evidence = visual.analyze_visual_obscuration(
        synthetic,
        source_sha256=synthetic_source_sha,
        roi_xyxy=synthetic_roi,
    )
    checks["synthetic_repeated_filled_components_detected"] = synthetic_evidence.get("obscuration_risk_proven") is True
    checks["synthetic_evidence_binding_valid"] = visual.verify_obscuration_evidence(
        synthetic_evidence,
        source_sha256=synthetic_source_sha,
        roi_sha256=synthetic_evidence.get("roi_sha256"),
        roi_xyxy=synthetic_roi,
    )

    # Negative geometry: repeated crossed strokes are not compact filled mask
    # components. Textual XXX therefore cannot be declared a mask from glyphs.
    crosses = _draw_cross_run()
    cross_source_sha = hashlib.sha256(b"synthetic-cross-v8").hexdigest()
    cross_roi = [0, 0, crosses.shape[1], crosses.shape[0]]
    cross_evidence = visual.analyze_visual_obscuration(
        crosses,
        source_sha256=cross_source_sha,
        roi_xyxy=cross_roi,
    )
    checks["cross_strokes_do_not_prove_visual_obscuration"] = cross_evidence.get("obscuration_risk_proven") is False

    # AUD-03 core: the same source pixels can be rendered by OCR as different
    # glyph families. Visual evidence, not glyph enumeration, must block exact
    # truth for every representation.
    unsupported = [
        "ju●●●@gmail.com",
        "ju███@gmail.com",
        "juXXX@gmail.com",
        "ju###@gmail.com",
        "ju…@gmail.com",
        "ju∗∗∗@gmail.com",
        "ju**@gmail.com",
    ]
    decisions: dict[str, str] = {}
    for value in unsupported:
        routed = router.route_observation(observation_for(
            value,
            fixture_evidence,
            source_sha=v6.GOVERNED_SOURCE_SHA256,
            roi_sha=fixture_roi_sha,
            roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
        ))
        decisions[value] = str(routed.get("decision"))
    checks["unsupported_ocr_glyphs_blocked_by_visual_evidence"] = all(
        decision == "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"
        for decision in decisions.values()
    )

    # The gate must precede normal machine-valid consensus and must never invoke
    # Paddle to hallucinate the hidden characters.
    visual_route = router.route_observation(observation_for(
        "juXXX@gmail.com",
        fixture_evidence,
        source_sha=v6.GOVERNED_SOURCE_SHA256,
        roi_sha=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    ))
    checks["visual_gate_is_unresolved"] = visual_route.get("resolved") is False
    checks["visual_gate_disables_challenger"] = visual_route.get("invoke_paddle") is False
    checks["visual_gate_emits_no_exact_text"] = visual_route.get("text") is None

    # Canonical evidence integrity and observation binding are mandatory.
    tampered = copy.deepcopy(fixture_evidence)
    tampered["max_repeated_component_run"] = int(tampered["max_repeated_component_run"]) + 1
    checks["tampered_visual_evidence_rejected"] = not visual.verify_obscuration_evidence(
        tampered,
        source_sha256=v6.GOVERNED_SOURCE_SHA256,
        roi_sha256=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    )
    tampered_route = router.route_observation(observation_for(
        "juXXX@gmail.com",
        tampered,
        source_sha=v6.GOVERNED_SOURCE_SHA256,
        roi_sha=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    ))
    checks["tampered_evidence_cannot_trigger_visual_gate"] = tampered_route.get("decision") != "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"

    wrong_source_route = router.route_observation(observation_for(
        "juXXX@gmail.com",
        fixture_evidence,
        source_sha=hashlib.sha256(b"different-source").hexdigest(),
        roi_sha=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    ))
    checks["cross_source_evidence_cannot_trigger_visual_gate"] = wrong_source_route.get("decision") != "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"

    wrong_roi_route = router.route_observation(observation_for(
        "juXXX@gmail.com",
        fixture_evidence,
        source_sha=v6.GOVERNED_SOURCE_SHA256,
        roi_sha=hashlib.sha256(b"different-roi").hexdigest(),
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    ))
    checks["cross_roi_evidence_cannot_trigger_visual_gate"] = wrong_roi_route.get("decision") != "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"

    # No source visual evidence: preserve the text-only boundary rather than
    # declaring unsupported glyphs to be masks by fiat.
    plain = router.route_observation(observation_for(
        "juXXX@gmail.com",
        None,
        source_sha=v6.GOVERNED_SOURCE_SHA256,
        roi_sha=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    ))
    checks["unsupported_text_without_visual_evidence_not_reclassified"] = plain.get("decision") != "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"

    normal = router.route_observation(observation_for(
        "alpha@example.com",
        None,
        source_sha=v6.GOVERNED_SOURCE_SHA256,
        roi_sha=fixture_roi_sha,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    ))
    checks["normal_email_without_visual_risk_preserved"] = normal.get("resolved") is True and normal.get("text") == "alpha@example.com"

    failed = sorted(name for name, ok in checks.items() if not ok)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V8" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V8",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "fixture_detector_summary": {
            "threshold": fixture_evidence.get("threshold"),
            "candidate_component_count": fixture_evidence.get("candidate_component_count"),
            "max_repeated_component_run": fixture_evidence.get("max_repeated_component_run"),
            "obscuration_risk_proven": fixture_evidence.get("obscuration_risk_proven"),
        },
        "unsupported_decisions": decisions,
        "remediated_findings": ["AUD-03"],
        "invariant": "SOURCE_BOUND_VISUAL_OBSCURATION_RISK_BLOCKS_EXACT_STRUCTURED_TRUTH_INDEPENDENT_OF_OCR_GLYPH",
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
        "sealed_holdout_accessed": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V8:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
