#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPO_ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
CONTRACT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(CONTRACT_ROOT))

import p0_multiscreen_structural_generalization_v1 as subject
import P0_SELECTIVE_OCR_ROUTER_V2 as router
from P0_CROP_COMPLETENESS_GUARD_V1 import text_crop_has_clear_margin


def t_attempt(variant_id: str, text: str, **untrusted: object) -> dict:
    return {"engine_family": "TESSERACT", "variant_id": variant_id, "text": text, **untrusted}


def p_attempt(variant_id: str, text: str, **untrusted: object) -> dict:
    return {"engine_family": "PADDLE", "variant_id": variant_id, "text": text, **untrusted}


def draw_cells(count: int, misaligned: bool = False) -> np.ndarray:
    image = np.full((260, 900, 3), 255, dtype=np.uint8)
    for index in range(count):
        x = 70 + index * 106
        y = 80 + (22 if misaligned and index % 2 else 0)
        cv2.rectangle(image, (x, y), (x + 74, y + 90), (0, 0, 0), 2)
    return image


def mask_image(plus_shapes: bool = False) -> tuple[np.ndarray, dict]:
    image = np.full((60, 120, 3), 255, dtype=np.uint8)
    for x, y in [(30, 30), (50, 30), (70, 30)]:
        if plus_shapes:
            cv2.line(image, (x - 5, y), (x + 5, y), (0, 0, 0), 2)
            cv2.line(image, (x, y - 5), (x, y + 5), (0, 0, 0), 2)
        else:
            cv2.circle(image, (x, y), 4, (0, 0, 0), -1)
    return image, {"x": 24, "y": 24, "width": 53, "height": 13}


def main() -> int:
    checks: dict[str, bool] = {}

    cells = subject.detect_segmented_input_cells(draw_cells(6))
    checks["six_cells_detected"] = len(cells) == 6
    checks["one_segmented_group"] = len({c.get("repeated_control_group_id") for c in cells}) == 1
    checks["three_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(3)) == []
    checks["misaligned_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(6, True)) == []

    dots, region = mask_image(False)
    pluses, plus_region = mask_image(True)
    checks["filled_dots_normalize"] = subject.normalize_repeated_mask_token(dots, region, "+++") == "•••"
    checks["real_plus_preserved"] = subject.normalize_repeated_mask_token(pluses, plus_region, "+++") is None

    # Crop-completeness guard: foreground touching an edge means the crop is not
    # eligible to diagnose an OCR failure. Clear margins allow OCR routing.
    clear = np.full((40, 120), 255, dtype=np.uint8)
    cv2.putText(clear, "18.00", (18, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65, 0, 1, cv2.LINE_AA)
    clipped = clear[:, :70].copy()
    checks["clear_text_crop_eligible"] = text_crop_has_clear_margin(clear, margin_px=2)
    checks["edge_clipped_text_crop_rejected"] = not text_crop_has_clear_margin(clipped, margin_px=2)

    source_bound = {
        "s02_mask": {
            "materiality": "TEXT", "kind": "generic_text", "baseline_text": "+++ 321",
            "structural_resolution_proven": True,
            "structural_resolution_code": "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
            "challenger_allowed": True,
        },
        "s02_cells": {
            "materiality": "NON_TEXT_CONTROL", "kind": "generic_text", "baseline_text": "HOOO0O",
            "challenger_allowed": True,
        },
        "s03_email": {
            "materiality": "TEXT", "kind": "email", "baseline_text": "",
            "targeted_attempts": [
                t_attempt("psm6-tight", "tucorreoO'email.com", valid=True, stable=True, confidence=0.999),
                t_attempt("psm7-tight", "tucorreoO'email.com", valid=True, stable=True),
                t_attempt("psm11-tight", "tucorreoOemail.com", valid=True, stable=True),
            ],
            "challenger_allowed": True,
        },
        "cand06_qr": {
            "materiality": "NON_TEXT_QR", "kind": "generic_text", "baseline_text": "cn ES Ea E paga pe",
            "challenger_allowed": True,
        },
        "cand07_card": {
            "materiality": "TEXT", "kind": "card_number", "baseline_text": "4 5 5 6 12 56",
            "targeted_attempts": [
                t_attempt("psm6-form", "1234 5678 9012 3456"),
                t_attempt("psm11-form", "1234 5678 9012 3456"),
                t_attempt("psm12-form", "1234 5678 9012 3456"),
            ],
            "challenger_allowed": True,
        },
        "cand08_sep_amount": {
            "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 211.19",
            "targeted_attempts": [
                t_attempt("psm6-up2", "S/ 211.19"),
                t_attempt("psm7-up2", "S/ 211.19"),
                t_attempt("psm11-up2", "S/ 211.19"),
            ],
            "challenger_allowed": True,
        },
        # PR162 correction: the earlier source-bound crop was clipped at the
        # right edge. A complete crop of the governed source reproduces the
        # visible amount exactly in PSM 6/7/11/12 and at multiple scales.
        "cand10_igv": {
            "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 1",
            "targeted_attempts": [
                t_attempt("psm6-complete", "S/ 18.00"),
                t_attempt("psm7-complete", "S/ 18.00"),
                t_attempt("psm11-complete", "S/ 18.00"),
            ],
            "challenger_allowed": True,
        },
    }
    expected = {
        "s02_mask": "STRUCTURAL_PIXEL_RESOLVED",
        "s02_cells": "DISCARD_NON_TEXT_OCR",
        "s03_email": "PADDLE_REQUIRED",
        "cand06_qr": "DISCARD_NON_TEXT_OCR",
        "cand07_card": "TARGETED_TESSERACT_ACCEPT",
        "cand08_sep_amount": "TARGETED_TESSERACT_ACCEPT",
        "cand10_igv": "TARGETED_TESSERACT_ACCEPT",
    }
    for name, observation in source_bound.items():
        checks[f"route_{name}"] = router.route_observation(observation).get("decision") == expected[name]

    paddle_cases = [
        name for name, observation in source_bound.items()
        if router.route_observation(observation).get("decision") == "PADDLE_REQUIRED"
    ]
    checks["one_real_persistent_paddle_trigger"] = paddle_cases == ["s03_email"]
    checks["complete_igv_crop_stops_paddle"] = not router.route_observation(source_bound["cand10_igv"]).get("invoke_paddle")

    checks["duplicate_variant_cannot_fake_consensus"] = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [t_attempt("same", "a@b.com"), t_attempt("same", "a@b.com")],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["caller_valid_stable_confidence_cannot_bypass"] = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("one", "still-bad", valid=True, stable=True, confidence=0.99999),
            t_attempt("two", "still-bad", valid=True, stable=True, confidence=0.99999),
        ],
        "challenger_allowed": True,
    }).get("decision") == "PADDLE_REQUIRED"
    checks["two_distinct_valid_variants_create_consensus"] = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [t_attempt("one", "a@b.com"), t_attempt("two", "a@b.com")],
        "challenger_allowed": True,
    }).get("decision") == "TARGETED_TESSERACT_ACCEPT"
    checks["unstructured_text_never_self_validates"] = router.route_observation({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "garbled",
        "targeted_attempts": [t_attempt("one", "different"), t_attempt("two", "different")],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["visible_truncation_never_completed"] = router.route_observation({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "Política de priv...",
        "visible_truncated": True,
        "targeted_attempts": [t_attempt("one", "Política de privacidad"), t_attempt("two", "Política de privacidad")],
        "challenger_allowed": True,
    }).get("decision") == "VISIBLE_ONLY_NO_COMPLETION"

    # Synthetic Paddle contract remains covered independently of the corrected
    # real IGV case. No real Paddle outcome is claimed by this regression.
    synthetic_paddle_target = {
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18",
        "targeted_attempts": [t_attempt("bad-a", "S/ 18"), t_attempt("bad-b", "S/ 18.1")],
        "challenger_allowed": True,
    }
    checks["synthetic_target_authorizes_paddle"] = router.route_observation(synthetic_paddle_target).get("decision") == "PADDLE_REQUIRED"
    good = [p_attempt("run-1", "S/ 18.00"), p_attempt("run-2", "S/ 18.00")]
    fixed = router.reconcile_paddle(synthetic_paddle_target, good)
    checks["two_paddle_variants_can_repair_machine_failure"] = fixed.get("decision") == "PADDLE_STRUCTURAL_CORRECTION" and fixed.get("text") == "S/ 18.00"
    checks["one_paddle_variant_cannot_claim_stability"] = router.reconcile_paddle(
        synthetic_paddle_target, [p_attempt("only", "S/ 18.00")]
    ).get("decision") == "NEEDS_REVIEW"
    checks["different_valid_paddle_values_abstain"] = router.reconcile_paddle(
        synthetic_paddle_target, [p_attempt("a", "S/ 18.00"), p_attempt("b", "S/ 19.00")]
    ).get("decision") == "NEEDS_REVIEW"
    checks["paddle_not_authorized_after_tesseract_success"] = router.reconcile_paddle(
        source_bound["cand10_igv"], good
    ).get("decision") == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"

    failed = sorted(name for name, passed in checks.items() if not passed)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V2" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V2",
        "checks": checks,
        "check_count": len(checks),
        "failed": failed,
        "source_bound_technical_cases": len(source_bound),
        "governed_source_images_available": 10,
        "persistent_paddle_required_cases": 1,
        "persistent_paddle_required_case_names": ["s03_email"],
        "pr162_false_trigger_corrected": "cand10_igv",
        "pr162_false_trigger_root_cause": "EDGE_CLIPPED_CROP",
        "real_paddle_outcome_for_new_case": "NOT_EXECUTED",
        "crop_completeness_guard_required": True,
        "paddle_runtime_promoted": False,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V2:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
