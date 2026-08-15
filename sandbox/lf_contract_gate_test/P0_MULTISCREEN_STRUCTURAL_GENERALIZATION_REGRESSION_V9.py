#!/usr/bin/env python3
"""PR166 remediation lot 05: mandatory pixel-first visual evidence regression.

V9 preserves V8 and independently attacks the audit failures found on
93c8157a: opt-in evidence bypass, material false positives, fixed-pixel scale
limits, dark-mode/touching masks, replay across observations and forgeable
self-seals.
"""
from __future__ import annotations

import copy
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V8 as v8
import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V6 as v6
import P0_SELECTIVE_OCR_ROUTER_V5 as router
import P0_VISUAL_OBSCURATION_EVIDENCE_V2 as visual


def t_attempt(variant_id: str, text: str, profile: str) -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": profile,
    }


def p_attempt(variant_id: str, text: str) -> dict:
    return {"engine_family": "PADDLE", "variant_id": variant_id, "text": text}


def _sha(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def _roi(image: np.ndarray, x: int = 0, y: int = 0) -> list[int]:
    return [x, y, x + image.shape[1], y + image.shape[0]]


def observation_for(
    text: str,
    image: np.ndarray | None,
    *,
    observation_id: str,
    kind: str = "email",
    source_sha: str | None = None,
    evidence: dict | None = None,
) -> dict:
    result = {
        "observation_id": observation_id,
        "materiality": "TEXT",
        "kind": kind,
        "baseline_text": text,
        "targeted_attempts": [
            t_attempt("v1", text, "eng"),
            t_attempt("v2", text, "spa"),
        ],
        "challenger_allowed": True,
        "source_sha256": source_sha or _sha("source:" + observation_id),
    }
    if image is not None:
        result["source_roi_gray"] = image
        result["roi_xyxy"] = _roi(image)
        result["roi_sha256"] = hashlib.sha256(image.tobytes(order="C")).hexdigest()
    if evidence is not None:
        result["visual_obscuration_evidence"] = evidence
    return result


def _font(size: int = 18):
    try:
        return ImageFont.truetype("DejaVuSans.ttf", size)
    except OSError:
        return ImageFont.load_default()


def _draw_text(value: str, *, dark: bool = False, scale: int = 1) -> np.ndarray:
    width = 420 * scale
    height = 52 * scale
    background = 0 if dark else 255
    foreground = 255 - background
    image = Image.new("L", (width, height), background)
    draw = ImageDraw.Draw(image)
    draw.text((5 * scale, 8 * scale), value, font=_font(22 * scale), fill=foreground)
    return np.asarray(image, dtype=np.uint8)


def _draw_standalone_squares(*, count: int = 3, size: int = 8) -> np.ndarray:
    image = np.full((32, 160), 255, dtype=np.uint8)
    for index in range(count):
        x = 30 + index * (size + 8)
        image[12:12 + size, x:x + size] = 0
    return image


def _draw_ellipsis() -> np.ndarray:
    image = np.full((32, 160), 255, dtype=np.uint8)
    for x in (65, 76, 87):
        image[20:23, x:x + 3] = 0
    return image


def _draw_masked_email(*, component_size: int = 8, scale: int = 1, dark: bool = False, touching: bool = False) -> np.ndarray:
    height = 52 * scale
    width = 440 * scale
    background = 0 if dark else 255
    foreground = 255 - background
    image = Image.new("L", (width, height), background)
    draw = ImageDraw.Draw(image)
    font = _font(22 * scale)
    draw.text((5 * scale, 8 * scale), "ju", font=font, fill=foreground)
    x0 = 45 * scale
    y0 = 20 * scale
    size = component_size * scale
    if touching:
        draw.rectangle((x0, y0, x0 + 3 * size - 1, y0 + size - 1), fill=foreground)
        tail_x = x0 + 3 * size + 10 * scale
    else:
        gap = max(4 * scale, size // 2)
        for index in range(3):
            left = x0 + index * (size + gap)
            draw.rectangle((left, y0, left + size - 1, y0 + size - 1), fill=foreground)
        tail_x = x0 + 3 * (size + gap) + 5 * scale
    draw.text((tail_x, 8 * scale), "@gmail.com", font=font, fill=foreground)
    return np.asarray(image, dtype=np.uint8)


def _evidence(image: np.ndarray, *, observation_id: str, kind: str = "email", source_sha: str | None = None) -> dict:
    return visual.analyze_visual_obscuration(
        image,
        observation_id=observation_id,
        kind=kind,
        source_sha256=source_sha or _sha("source:" + observation_id),
        roi_xyxy=_roi(image),
    )


def main() -> int:
    if v8.main() != 0:
        raise SystemExit("FAIL_V8_PREREQUISITE")

    checks: dict[str, bool] = {}

    fixture, fixture_roi_sha = v6.load_fixture()
    real_evidence = visual.analyze_visual_obscuration(
        fixture,
        observation_id="pr166-real-masked-email",
        kind="email",
        source_sha256=v6.GOVERNED_SOURCE_SHA256,
        roi_xyxy=v6.SOURCE_TEXT_ROI_XYXY,
    )
    checks["real_fixture_v2_roi_sha_exact"] = real_evidence.get("roi_sha256") == fixture_roi_sha
    checks["real_fixture_v2_visual_risk_detected"] = real_evidence.get("obscuration_risk_proven") is True

    no_supplied_evidence = observation_for(
        "juNNN@gmail.com",
        fixture,
        observation_id="pr166-real-masked-email",
        source_sha=v6.GOVERNED_SOURCE_SHA256,
    )
    no_supplied_evidence["roi_xyxy"] = list(v6.SOURCE_TEXT_ROI_XYXY)
    no_supplied_evidence["roi_sha256"] = fixture_roi_sha
    route = router.route_observation(no_supplied_evidence)
    checks["masked_source_without_supplied_evidence_still_blocks"] = route.get("decision") == "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"
    checks["masked_source_without_supplied_evidence_unresolved"] = route.get("resolved") is False
    checks["masked_source_without_supplied_evidence_no_paddle"] = route.get("invoke_paddle") is False

    missing_pixels = observation_for("alpha@example.com", None, observation_id="missing-pixels")
    checks["machine_validated_kind_without_pixels_fails_closed"] = (
        router.route_observation(missing_pixels).get("decision") == "VISUAL_SOURCE_EVIDENCE_REQUIRED"
    )

    for index, value in enumerate(("alpha@example.com", "tucorreo@email.com", "nnn.mmm@correo.com"), start=1):
        image = _draw_text(value)
        evidence = _evidence(image, observation_id=f"normal-{index}")
        routed = router.route_observation(observation_for(value, image, observation_id=f"normal-{index}"))
        checks[f"normal_text_pixels_not_obscuration_{index}"] = evidence.get("obscuration_risk_proven") is False
        checks[f"normal_text_route_preserved_{index}"] = routed.get("resolved") is True and routed.get("text") == value

    squares = _draw_standalone_squares()
    ellipsis = _draw_ellipsis()
    checks["three_standalone_squares_not_obscuration"] = _evidence(squares, observation_id="legit-squares").get("obscuration_risk_proven") is False
    checks["ellipsis_dots_not_obscuration"] = _evidence(ellipsis, observation_id="legit-ellipsis").get("obscuration_risk_proven") is False

    for size in (6, 12, 24, 36):
        image = _draw_masked_email(component_size=size, scale=2 if size >= 24 else 1)
        checks[f"mask_scale_{size}_detected"] = _evidence(image, observation_id=f"scale-{size}").get("obscuration_risk_proven") is True
    dark_mask = _draw_masked_email(component_size=10, dark=True)
    checks["light_mask_on_dark_detected"] = _evidence(dark_mask, observation_id="dark-mask").get("obscuration_risk_proven") is True
    touching = _draw_masked_email(component_size=10, touching=True)
    checks["touching_filled_mask_detected"] = _evidence(touching, observation_id="touching-mask").get("obscuration_risk_proven") is True

    clear = _draw_text("alpha@example.com")
    clear_source = _sha("source:clear-a")
    clear_evidence = _evidence(clear, observation_id="clear-a", source_sha=clear_source)
    forged = copy.deepcopy(clear_evidence)
    forged["obscuration_risk_proven"] = True
    forged["max_repeated_component_run"] = 3
    forged.pop("evidence_sha256", None)
    forged["evidence_sha256"] = hashlib.sha256(visual._canonical_bytes(forged)).hexdigest()
    checks["forged_resealed_positive_rejected"] = not visual.verify_obscuration_evidence(
        forged,
        clear,
        observation_id="clear-a",
        kind="email",
        source_sha256=clear_source,
        roi_xyxy=_roi(clear),
    )
    checks["cross_observation_replay_rejected"] = not visual.verify_obscuration_evidence(
        clear_evidence,
        clear,
        observation_id="clear-b",
        kind="email",
        source_sha256=clear_source,
        roi_xyxy=_roi(clear),
    )
    checks["cross_kind_replay_rejected"] = not visual.verify_obscuration_evidence(
        clear_evidence,
        clear,
        observation_id="clear-a",
        kind="currency",
        source_sha256=clear_source,
        roi_xyxy=_roi(clear),
    )

    forged_route = router.route_observation(observation_for(
        "alpha@example.com",
        clear,
        observation_id="clear-a",
        source_sha=clear_source,
        evidence=forged,
    ))
    checks["forged_supplied_evidence_cannot_enter_gate"] = forged_route.get("decision") == "VISUAL_EVIDENCE_BINDING_INVALID"

    replay_route = router.route_observation(observation_for(
        "alpha@example.com",
        clear,
        observation_id="clear-b",
        source_sha=clear_source,
        evidence=clear_evidence,
    ))
    checks["replayed_supplied_evidence_cannot_enter_gate"] = replay_route.get("decision") == "VISUAL_EVIDENCE_BINDING_INVALID"

    literal_x = _draw_text("juXXX@gmail.com")
    literal_route = router.route_observation(observation_for(
        "juXXX@gmail.com",
        literal_x,
        observation_id="literal-xxx",
    ))
    checks["literal_xxx_with_clear_pixels_not_auto_masked"] = literal_route.get("resolved") is True and literal_route.get("text") == "juXXX@gmail.com"

    unsupported = [
        "ju●●●@gmail.com",
        "ju███@gmail.com",
        "juXXX@gmail.com",
        "ju###@gmail.com",
        "ju…@gmail.com",
        "ju∗∗∗@gmail.com",
        "ju**@gmail.com",
    ]
    for index, value in enumerate(unsupported, start=1):
        obs = observation_for(
            value,
            fixture,
            observation_id=f"masked-rendering-{index}",
            source_sha=v6.GOVERNED_SOURCE_SHA256,
        )
        obs["roi_xyxy"] = list(v6.SOURCE_TEXT_ROI_XYXY)
        obs["roi_sha256"] = fixture_roi_sha
        blocked = router.route_observation(obs)
        checks[f"masked_pixels_block_rendering_{index}"] = (
            blocked.get("decision") == "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH"
            and blocked.get("resolved") is False
            and blocked.get("text") is None
        )

    paddle = router.reconcile_paddle(
        no_supplied_evidence,
        [p_attempt("p1", "invented@example.com"), p_attempt("p2", "invented@example.com")],
    )
    checks["masked_pixels_block_paddle_reconstruction"] = (
        paddle.get("decision") == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"
        and paddle.get("resolved") is False
        and paddle.get("text") is None
    )

    failed = sorted(name for name, ok in checks.items() if not ok)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V9" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V9",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "real_fixture_detector_summary": {
            "threshold": real_evidence.get("threshold"),
            "selected_polarity": real_evidence.get("selected_polarity"),
            "candidate_component_count": real_evidence.get("candidate_component_count"),
            "max_repeated_component_run": real_evidence.get("max_repeated_component_run"),
            "compound_filled_run_count": real_evidence.get("compound_filled_run_count"),
            "text_like_context_count": real_evidence.get("text_like_context_count"),
            "obscuration_risk_proven": real_evidence.get("obscuration_risk_proven"),
        },
        "remediated_audit_findings": [
            "AUD-04_OPT_IN_VISUAL_GATE",
            "AUD-05_MATERIAL_FALSE_POSITIVE",
            "AUD-06_FIXED_PIXEL_SCALE_FALSE_NEGATIVE",
            "AUD-07_DARK_MODE_TOUCHING_FALSE_NEGATIVE",
            "AUD-08_UNAUTHENTICATED_SELF_SEAL",
            "CROSS_OBSERVATION_REPLAY",
        ],
        "invariant": "MACHINE_VALIDATED_STRUCTURED_TEXT_REQUIRES_PIXEL_DERIVED_OBSERVATION_BOUND_VISUAL_PREFLIGHT",
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
        "sealed_holdout_accessed": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V9:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
