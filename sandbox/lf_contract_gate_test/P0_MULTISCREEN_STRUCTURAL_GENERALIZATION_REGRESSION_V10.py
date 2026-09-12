#!/usr/bin/env python3
"""PR166 final consolidated structural generalization regression.

V10 preserves V9 and closes the independent-audit family at the cause boundary:
- 2-component masks cannot release exact truth;
- visual decisions are based on local geometry and remain stable under ROI padding;
- legitimate repeated UI geometry is not treated as inline obscuration;
- ambiguous visual evidence is a first-class abstention state;
- evidence remains pixel-recomputed and observation/source/ROI bound;
- a deterministic 5,120-case generative campaign exercises the safety boundary.
"""
from __future__ import annotations

import copy
import hashlib
import io
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V9 as v9
import P0_SELECTIVE_OCR_ROUTER_V5 as router
import P0_VISUAL_OBSCURATION_EVIDENCE_V3 as visual


FUZZ_SEED = 16605120
FUZZ_CASES = 5120


def _sha(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def _roi(image: np.ndarray, x: int = 0, y: int = 0) -> list[int]:
    return [x, y, x + image.shape[1], y + image.shape[0]]


def _font(size: int = 18):
    try:
        return ImageFont.truetype("DejaVuSans.ttf", size)
    except OSError:
        return ImageFont.load_default()


def _evidence(
    image: np.ndarray,
    *,
    observation_id: str,
    kind: str = "email",
    source_sha: str | None = None,
    roi_xyxy: list[int] | None = None,
) -> dict:
    return visual.analyze_visual_obscuration(
        image,
        observation_id=observation_id,
        kind=kind,
        source_sha256=source_sha or _sha("source:" + observation_id),
        roi_xyxy=roi_xyxy or _roi(image),
    )


def _t_attempt(variant_id: str, text: str, profile: str) -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": profile,
    }


def _p_attempt(variant_id: str, text: str) -> dict:
    return {"engine_family": "PADDLE", "variant_id": variant_id, "text": text}


def _observation(
    text: str,
    image: np.ndarray,
    *,
    observation_id: str,
    kind: str = "email",
    source_sha: str | None = None,
    evidence: dict | None = None,
) -> dict:
    source = source_sha or _sha("source:" + observation_id)
    result = {
        "observation_id": observation_id,
        "materiality": "TEXT",
        "kind": kind,
        "baseline_text": text,
        "targeted_attempts": [
            _t_attempt("v1", text, "eng"),
            _t_attempt("v2", text, "spa"),
        ],
        "challenger_allowed": True,
        "source_sha256": source,
        "source_roi_gray": image,
        "roi_xyxy": _roi(image),
        "roi_sha256": hashlib.sha256(image.tobytes(order="C")).hexdigest(),
    }
    if evidence is not None:
        result["visual_obscuration_evidence"] = evidence
    return result


def _draw_text(value: str, *, dark: bool = False, scale: int = 1) -> np.ndarray:
    width = 440 * scale
    height = 52 * scale
    background = 0 if dark else 255
    foreground = 255 - background
    image = Image.new("L", (width, height), background)
    draw = ImageDraw.Draw(image)
    draw.text((5 * scale, 8 * scale), value, font=_font(22 * scale), fill=foreground)
    return np.asarray(image, dtype=np.uint8)


def _draw_masked_email(
    *,
    count: int = 3,
    component_size: int = 8,
    dark: bool = False,
    touching: bool = False,
) -> np.ndarray:
    height = 52
    width = 440
    background = 0 if dark else 255
    foreground = 255 - background
    image = Image.new("L", (width, height), background)
    draw = ImageDraw.Draw(image)
    font = _font(22)
    draw.text((5, 8), "ju", font=font, fill=foreground)
    x0 = 45
    y0 = 20
    size = component_size
    if touching:
        draw.rectangle((x0, y0, x0 + count * size - 1, y0 + size - 1), fill=foreground)
        tail_x = x0 + count * size + 7
    else:
        gap = max(3, size // 2)
        for index in range(count):
            left = x0 + index * (size + gap)
            draw.rectangle((left, y0, left + size - 1, y0 + size - 1), fill=foreground)
        tail_x = x0 + count * (size + gap) + 3
    draw.text((tail_x, 8), "@gmail.com", font=font, fill=foreground)
    return np.asarray(image, dtype=np.uint8)


def _pad(image: np.ndarray, *, horizontal_pct: int = 0, vertical_pct: int = 0) -> np.ndarray:
    background = int(image[0, 0])
    py = int(round(image.shape[0] * vertical_pct / 200.0))
    px = int(round(image.shape[1] * horizontal_pct / 200.0))
    return np.pad(image, ((py, py), (px, px)), constant_values=background)


def _draw_pagination() -> np.ndarray:
    image = Image.new("L", (240, 72), 255)
    draw = ImageDraw.Draw(image)
    draw.text((10, 6), "Page", font=_font(20), fill=0)
    for index in range(4):
        x = 86 + index * 17
        draw.ellipse((x, 48, x + 7, 55), fill=0)
    return np.asarray(image, dtype=np.uint8)


def _draw_loader() -> np.ndarray:
    image = np.full((50, 180), 255, dtype=np.uint8)
    for index in range(3):
        x = 60 + index * 16
        image[20:28, x:x + 8] = 0
    return image


def _draw_progress_dots() -> np.ndarray:
    image = Image.new("L", (260, 72), 255)
    draw = ImageDraw.Draw(image)
    draw.text((15, 8), "Continue", font=_font(20), fill=0)
    for index in range(6):
        x = 78 + index * 14
        draw.ellipse((x, 50, x + 6, 56), fill=0)
    return np.asarray(image, dtype=np.uint8)


def _draw_rating() -> np.ndarray:
    image = Image.new("L", (260, 62), 255)
    draw = ImageDraw.Draw(image)
    draw.text((12, 8), "Rating", font=_font(20), fill=0)
    x = 100
    for index in range(5):
        cx = x + index * 22
        points = [(cx, 18), (cx + 4, 28), (cx + 14, 28), (cx + 6, 34), (cx + 10, 44),
                  (cx, 38), (cx - 10, 44), (cx - 6, 34), (cx - 14, 28), (cx - 4, 28)]
        draw.polygon(points, outline=0)
    return np.asarray(image, dtype=np.uint8)


def _draw_bullets() -> np.ndarray:
    image = Image.new("L", (260, 84), 255)
    draw = ImageDraw.Draw(image)
    for y, value in ((8, "One"), (40, "Two")):
        draw.ellipse((10, y + 8, 15, y + 13), fill=0)
        draw.text((26, y), value, font=_font(20), fill=0)
    return np.asarray(image, dtype=np.uint8)


def _draw_segmented_cells() -> np.ndarray:
    image = Image.new("L", (280, 62), 255)
    draw = ImageDraw.Draw(image)
    for index in range(6):
        x = 10 + index * 44
        draw.rectangle((x, 12, x + 32, 47), outline=0, width=2)
    return np.asarray(image, dtype=np.uint8)


def _draw_squares_near_text(count: int) -> np.ndarray:
    image = Image.new("L", (300, 62), 255)
    draw = ImageDraw.Draw(image)
    for index in range(count):
        x = 12 + index * 15
        draw.rectangle((x, 23, x + 7, 30), fill=0)
    draw.text((28 + count * 15, 9), "Status", font=_font(22), fill=0)
    return np.asarray(image, dtype=np.uint8)


def _draw_logo_shapes() -> np.ndarray:
    image = Image.new("L", (260, 70), 255)
    draw = ImageDraw.Draw(image)
    draw.rectangle((16, 18, 36, 38), fill=0)
    draw.ellipse((44, 18, 64, 38), fill=0)
    draw.polygon([(76, 38), (86, 18), (96, 38)], fill=0)
    draw.text((120, 12), "Brand", font=_font(22), fill=0)
    return np.asarray(image, dtype=np.uint8)


def _draw_ellipsis() -> np.ndarray:
    image = np.full((42, 180), 255, dtype=np.uint8)
    for x in (72, 84, 96):
        image[23:26, x:x + 3] = 0
    return image


def _distortions(base: np.ndarray) -> dict[str, np.ndarray]:
    output: dict[str, np.ndarray] = {}
    image = Image.fromarray(base)
    output["blur"] = np.asarray(image.filter(ImageFilter.GaussianBlur(radius=1.0)), dtype=np.uint8)
    encoded = io.BytesIO()
    image.save(encoded, format="JPEG", quality=45)
    encoded.seek(0)
    output["jpeg"] = np.asarray(Image.open(encoded).convert("L"), dtype=np.uint8)
    low = np.asarray(base, dtype=np.float32)
    output["low_contrast"] = np.where(low < 128, 145, 205).astype(np.uint8)
    antialias = image.resize((220, 26), Image.Resampling.LANCZOS).resize((440, 52), Image.Resampling.BILINEAR)
    output["antialias"] = np.asarray(antialias, dtype=np.uint8)
    noisy = base.copy()
    rng = np.random.default_rng(FUZZ_SEED)
    ys = rng.integers(0, noisy.shape[0], size=40)
    xs = rng.integers(0, noisy.shape[1], size=40)
    noisy[ys, xs] = 255 - noisy[ys, xs]
    output["noise"] = noisy
    return output


def _parametric_mask(index: int) -> tuple[np.ndarray, dict]:
    cardinalities = (2, 3, 4, 6, 8)
    sizes = (3, 4, 5, 6)
    gaps = (1, 2, 3, 4)
    paddings = (0, 2, 4, 8)
    polarities = ("dark_on_light", "light_on_dark")
    shapes = ("square", "oval")
    contrasts = (70, 140)
    baselines = (-2, 0, 2)
    noise_counts = (0, 1, 2, 3)

    config = {
        "cardinality": cardinalities[index % len(cardinalities)],
        "size": sizes[(index // 5) % len(sizes)],
        "spacing": gaps[(index // 20) % len(gaps)],
        "padding": paddings[(index // 80) % len(paddings)],
        "polarity": polarities[(index // 320) % len(polarities)],
        "shape": shapes[(index // 640) % len(shapes)],
        "contrast": contrasts[(index // 1280) % len(contrasts)],
        "baseline": baselines[(index // 7) % len(baselines)],
        "noise": noise_counts[(index // 11) % len(noise_counts)],
        "text_neighbor": "bilateral",
    }

    pad = int(config["padding"])
    if config["polarity"] == "dark_on_light":
        background = 230
        foreground = max(0, background - int(config["contrast"]))
    else:
        background = 25
        foreground = min(255, background + int(config["contrast"]))

    height = 26 + 2 * pad
    width = 112 + 2 * pad
    image = np.full((height, width), background, dtype=np.uint8)
    y0 = pad + 8
    glyph_h = 10
    image[y0:y0 + glyph_h, pad + 4:pad + 6] = foreground
    image[y0:y0 + glyph_h, pad + 9:pad + 11] = foreground

    count = int(config["cardinality"])
    size = int(config["size"])
    gap = int(config["spacing"])
    x0 = pad + 18
    mask_y = y0 + (glyph_h - size) // 2 + int(config["baseline"])
    for item_index in range(count):
        left = x0 + item_index * (size + gap)
        if config["shape"] == "square":
            image[mask_y:mask_y + size, left:left + size] = foreground
        else:
            yy, xx = np.ogrid[:size, :size]
            radius = (size - 1) / 2.0
            circle = (xx - radius) ** 2 + (yy - radius) ** 2 <= max(1.0, radius ** 2)
            crop = image[mask_y:mask_y + size, left:left + size]
            crop[circle] = foreground

    tail = x0 + count * (size + gap) + 3
    for item_index in range(5):
        gx = tail + item_index * 5
        image[y0:y0 + glyph_h, gx:gx + 2] = foreground

    for noise_index in range(int(config["noise"])):
        yy = pad + 1 + (noise_index * 3) % max(1, height - 2 * pad - 2)
        xx = width - pad - 2 - noise_index * 3
        if 0 <= yy < height and 0 <= xx < width:
            image[yy, xx] = foreground

    return image, config


def _record(checks: dict[str, bool], name: str, condition: bool) -> None:
    checks[name] = bool(condition)


def main() -> int:
    if v9.main() != 0:
        raise SystemExit("FAIL_V9_PREREQUISITE")

    checks: dict[str, bool] = {}

    # F01: 2-component masks must not be released. One component is explicitly
    # ambiguous rather than silently clear when embedded in the carrier.
    one = _draw_masked_email(count=1)
    two = _draw_masked_email(count=2)
    one_evidence = _evidence(one, observation_id="one-component")
    two_evidence = _evidence(two, observation_id="two-component")
    _record(checks, "one_component_is_ambiguous", one_evidence["visual_state"] == visual.STATE_AMBIGUOUS)
    _record(checks, "two_component_mask_is_risk", two_evidence["visual_state"] == visual.STATE_RISK)

    one_route = router.route_observation(_observation("juN@gmail.com", one, observation_id="one-component"))
    two_route = router.route_observation(_observation("juNN@gmail.com", two, observation_id="two-component"))
    _record(checks, "ambiguous_visual_evidence_blocks_exact_truth", one_route.get("decision") == "VISUAL_EVIDENCE_AMBIGUOUS_NO_EXACT_TRUTH" and one_route.get("resolved") is False and one_route.get("invoke_paddle") is False)
    _record(checks, "two_component_visual_risk_blocks_exact_truth", two_route.get("decision") == "VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH" and two_route.get("resolved") is False and two_route.get("invoke_paddle") is False)

    # F02: same visual evidence under ROI padding/crop context must preserve the
    # safety state because geometry is normalized locally.
    for vertical in (0, 10, 25, 50, 100, 200):
        padded = _pad(two, vertical_pct=vertical)
        _record(checks, f"vertical_padding_{vertical}_preserves_nonclear", _evidence(padded, observation_id=f"pad-v-{vertical}")["visual_state"] != visual.STATE_CLEAR)
    for horizontal in (0, 10, 25, 50, 100, 200):
        padded = _pad(two, horizontal_pct=horizontal)
        _record(checks, f"horizontal_padding_{horizontal}_preserves_nonclear", _evidence(padded, observation_id=f"pad-h-{horizontal}")["visual_state"] != visual.STATE_CLEAR)

    for ratio in (0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00):
        scaled = np.asarray(
            Image.fromarray(two).resize(
                (max(8, int(round(two.shape[1] * ratio))), max(8, int(round(two.shape[0] * ratio)))),
                Image.Resampling.LANCZOS,
            ),
            dtype=np.uint8,
        )
        _record(checks, f"scale_{ratio:g}_preserves_nonclear", _evidence(scaled, observation_id=f"scale-{ratio:g}")["visual_state"] != visual.STATE_CLEAR)

    dark = _draw_masked_email(count=2, dark=True)
    touching = _draw_masked_email(count=2, touching=True)
    _record(checks, "dark_mode_two_component_mask_nonclear", _evidence(dark, observation_id="dark-two")["visual_state"] != visual.STATE_CLEAR)
    _record(checks, "touching_two_component_mask_nonclear", _evidence(touching, observation_id="touching-two")["visual_state"] != visual.STATE_CLEAR)

    for name, distorted in _distortions(two).items():
        _record(checks, f"distortion_{name}_preserves_nonclear", _evidence(distorted, observation_id=f"distortion-{name}")["visual_state"] != visual.STATE_CLEAR)

    # F03: legitimate UI/text families remain CLEAR.
    legitimate: dict[str, np.ndarray] = {
        "normal_email": _draw_text("alpha@example.com"),
        "plus_tag_email": _draw_text("user+tag@example.com"),
        "literal_xxx": _draw_text("juXXX@gmail.com"),
        "unicode_email": _draw_text("müller@example.com"),
        "pagination": _draw_pagination(),
        "loader": _draw_loader(),
        "progress_dots": _draw_progress_dots(),
        "rating": _draw_rating(),
        "bullets": _draw_bullets(),
        "segmented_cells": _draw_segmented_cells(),
        "three_squares_near_text": _draw_squares_near_text(3),
        "four_squares_near_text": _draw_squares_near_text(4),
        "six_squares_near_text": _draw_squares_near_text(6),
        "logos_shapes": _draw_logo_shapes(),
        "ellipsis": _draw_ellipsis(),
    }
    false_positive_matrix: dict[str, str] = {}
    for name, image in legitimate.items():
        state = _evidence(image, observation_id="legit-" + name)["visual_state"]
        false_positive_matrix[name] = state
        _record(checks, f"legitimate_{name}_clear", state == visual.STATE_CLEAR)

    # Clear machine-validated kinds continue through their ordinary OCR contract.
    clear_values = {
        "email": "alpha@example.com",
        "currency": "S/ 18.00",
        "document": "12345678",
        "phone": "987654321",
        "card_number": "4111111111111111",
    }
    for kind, value in clear_values.items():
        image = _draw_text(value)
        routed = router.route_observation(_observation(value, image, observation_id="clear-" + kind, kind=kind))
        _record(checks, f"clear_{kind}_route_resolves", routed.get("resolved") is True and routed.get("text") == value and routed.get("visual_state") == visual.STATE_CLEAR)

    # OCR representation cannot override visual safety.
    valid_looking = {
        "email": "alpha@example.com",
        "currency": "S/ 18.00",
        "document": "12345678",
        "phone": "987654321",
        "card_number": "4111111111111111",
    }
    ocr_boundary_matrix: dict[str, str] = {}
    for kind, value in valid_looking.items():
        obs = _observation(value, two, observation_id="masked-valid-" + kind, kind=kind)
        routed = router.route_observation(obs)
        ocr_boundary_matrix[kind] = str(routed.get("decision"))
        _record(checks, f"masked_pixels_block_valid_looking_{kind}", routed.get("resolved") is False and routed.get("invoke_paddle") is False and routed.get("decision") in {"VISUAL_OBSCURATION_RISK_NO_EXACT_TRUTH", "VISUAL_EVIDENCE_AMBIGUOUS_NO_EXACT_TRUTH"})

    paddle = router.reconcile_paddle(
        _observation("alpha@example.com", two, observation_id="masked-paddle"),
        [_p_attempt("p1", "alpha@example.com"), _p_attempt("p2", "alpha@example.com")],
    )
    _record(checks, "masked_or_ambiguous_pixels_block_paddle", paddle.get("decision") == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION" and paddle.get("resolved") is False)

    # Pixel recomputation defeats re-seal and binding mutations.
    source_sha = _sha("source:mutation-base")
    clear_image = _draw_text("alpha@example.com")
    base_evidence = _evidence(clear_image, observation_id="mutation-base", source_sha=source_sha)
    mutation_rejections: dict[str, bool] = {}

    def rejected(name: str, evidence: dict, *, image: np.ndarray = clear_image, observation_id: str = "mutation-base", kind: str = "email", source: str = source_sha, coords: list[int] | None = None) -> None:
        mutation_rejections[name] = not visual.verify_obscuration_evidence(
            evidence,
            image,
            observation_id=observation_id,
            kind=kind,
            source_sha256=source,
            roi_xyxy=coords or _roi(image),
        )

    mutated_fields = {
        "visual_state": visual.STATE_RISK,
        "obscuration_risk_proven": True,
        "ambiguous_visual_evidence": True,
        "context_mode": "FORGED",
        "selected_polarity": "LIGHT_ON_DARK",
        "candidate_component_count": int(base_evidence["candidate_component_count"]) + 1,
        "local_scale_px": float(base_evidence["local_scale_px"]) + 1.0,
        "threshold": (int(base_evidence["threshold"]) + 1) % 256,
        "detector": "FORGED_DETECTOR",
        "schema_version": "forged/v999",
    }
    for field, value in mutated_fields.items():
        forged = copy.deepcopy(base_evidence)
        forged[field] = value
        forged.pop("evidence_sha256", None)
        forged["evidence_sha256"] = hashlib.sha256(visual._canonical_bytes(forged)).hexdigest()
        rejected("reseal_" + field, forged)

    rejected("cross_observation", base_evidence, observation_id="mutation-other")
    rejected("cross_kind", base_evidence, kind="currency")
    rejected("cross_source", base_evidence, source=_sha("source:other"))
    rejected("cross_coords", base_evidence, coords=[1, 0, clear_image.shape[1] + 1, clear_image.shape[0]])
    altered_pixels = clear_image.copy()
    altered_pixels[0, 0] = 255 - altered_pixels[0, 0]
    rejected("cross_pixels", base_evidence, image=altered_pixels)
    for name, ok in mutation_rejections.items():
        _record(checks, "evidence_mutation_" + name + "_rejected", ok)

    # Deterministic generative campaign. Safety criterion: generated masked
    # carriers may be RISK or AMBIGUOUS, but never CLEAR/releasable.
    fuzz_unsafe_clear = 0
    fuzz_risk = 0
    fuzz_ambiguous = 0
    coverage = {
        "cardinality": set(),
        "shape": set(),
        "size": set(),
        "spacing": set(),
        "contrast": set(),
        "polarity": set(),
        "padding": set(),
        "baseline": set(),
        "noise": set(),
        "text_neighbor": set(),
    }
    first_unsafe: dict | None = None
    for index in range(FUZZ_CASES):
        image, config = _parametric_mask(index)
        for dimension in coverage:
            coverage[dimension].add(config[dimension])
        evidence = _evidence(image, observation_id=f"fuzz-{FUZZ_SEED}-{index}")
        state = str(evidence["visual_state"])
        if state == visual.STATE_CLEAR:
            fuzz_unsafe_clear += 1
            if first_unsafe is None:
                first_unsafe = {"index": index, "config": config, "evidence": evidence}
        elif state == visual.STATE_RISK:
            fuzz_risk += 1
        elif state == visual.STATE_AMBIGUOUS:
            fuzz_ambiguous += 1
        else:
            fuzz_unsafe_clear += 1
            if first_unsafe is None:
                first_unsafe = {"index": index, "config": config, "evidence": evidence}

    _record(checks, "fuzz_5120_executed", fuzz_risk + fuzz_ambiguous + fuzz_unsafe_clear == FUZZ_CASES)
    _record(checks, "fuzz_zero_unsafe_clear", fuzz_unsafe_clear == 0)
    _record(checks, "fuzz_cardinality_coverage", coverage["cardinality"] == {2, 3, 4, 6, 8})
    _record(checks, "fuzz_shape_coverage", coverage["shape"] == {"square", "oval"})
    _record(checks, "fuzz_polarity_coverage", coverage["polarity"] == {"dark_on_light", "light_on_dark"})
    _record(checks, "fuzz_contrast_coverage", coverage["contrast"] == {70, 140})
    _record(checks, "fuzz_padding_coverage", coverage["padding"] == {0, 2, 4, 8})
    _record(checks, "fuzz_baseline_coverage", coverage["baseline"] == {-2, 0, 2})
    _record(checks, "fuzz_noise_coverage", coverage["noise"] == {0, 1, 2, 3})

    failed = sorted(name for name, ok in checks.items() if not ok)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V10" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V10",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "invariant": "VALID_SYNTAX_NEVER_IMPLIES_COMPLETE_VISUAL_OBSERVABILITY",
        "visual_contract": router.VISUAL_CONTRACT,
        "false_positive_matrix": false_positive_matrix,
        "ocr_boundary_matrix": ocr_boundary_matrix,
        "evidence_mutation_rejections": mutation_rejections,
        "fuzz": {
            "seed": FUZZ_SEED,
            "cases": FUZZ_CASES,
            "risk": fuzz_risk,
            "ambiguous": fuzz_ambiguous,
            "unsafe_clear": fuzz_unsafe_clear,
            "first_unsafe": first_unsafe,
            "coverage": {key: sorted(values, key=str) for key, values in coverage.items()},
        },
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
        "runtime_promoted": False,
        "sealed_holdout_accessed": False,
        "merge_authorized": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V10:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
