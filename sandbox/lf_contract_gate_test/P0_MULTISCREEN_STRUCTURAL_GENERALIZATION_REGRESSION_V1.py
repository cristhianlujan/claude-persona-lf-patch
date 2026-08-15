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


def fail(code: str, detail: str = "") -> None:
    raise SystemExit(code if not detail else f"{code}:{detail}")


def blank(width: int = 900, height: int = 260) -> np.ndarray:
    return np.full((height, width, 3), 255, dtype=np.uint8)


def draw_cells(count: int, *, misaligned: bool = False) -> np.ndarray:
    image = blank()
    for index in range(count):
        x = 70 + index * 106
        y = 80 + (22 if misaligned and index % 2 else 0)
        cv2.rectangle(image, (x, y), (x + 74, y + 90), (0, 0, 0), 2)
    return image


def mask_image(*, plus_shapes: bool = False) -> tuple[np.ndarray, dict]:
    image = np.full((60, 120, 3), 255, dtype=np.uint8)
    centers = [(30, 30), (50, 30), (70, 30)]
    if plus_shapes:
        for x, y in centers:
            cv2.line(image, (x - 5, y), (x + 5, y), (0, 0, 0), 2)
            cv2.line(image, (x, y - 5), (x, y + 5), (0, 0, 0), 2)
    else:
        for x, y in centers:
            cv2.circle(image, (x, y), 4, (0, 0, 0), -1)
    return image, {"x": 24, "y": 24, "width": 53, "height": 13}


def route(observation: dict) -> dict:
    return router.route_observation(observation)


def t_attempt(variant_id: str, text: str, **untrusted: object) -> dict:
    return {"engine_family": "TESSERACT", "variant_id": variant_id, "text": text, **untrusted}


def p_attempt(variant_id: str, text: str, **untrusted: object) -> dict:
    return {"engine_family": "PADDLE", "variant_id": variant_id, "text": text, **untrusted}


def main() -> int:
    checks: dict[str, bool] = {}

    # PR161 structural regressions remain mandatory.
    positive_cells = subject.detect_segmented_input_cells(draw_cells(6))
    checks["six_cells_detected"] = len(positive_cells) == 6
    checks["one_segmented_group"] = len({item.get("repeated_control_group_id") for item in positive_cells}) == 1
    checks["generic_control_type"] = all(item.get("control_type") == "SEGMENTED_INPUT_CELL" for item in positive_cells)
    checks["three_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(3)) == []
    checks["misaligned_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(6, misaligned=True)) == []

    dot_image, dot_region = mask_image(plus_shapes=False)
    plus_image, plus_region = mask_image(plus_shapes=True)
    checks["filled_dots_normalize"] = subject.normalize_repeated_mask_token(dot_image, dot_region, "+++") == "•••"
    checks["real_plus_shapes_preserved"] = subject.normalize_repeated_mask_token(plus_image, plus_region, "+++") is None
    checks["ordinary_text_not_normalized"] = subject.normalize_repeated_mask_token(dot_image, dot_region, "abc") is None

    candidate = {
        "elements": [{
            "element_id": "T-MASK",
            "element_type": "TEXT",
            "visible_text": "terminado en +++ 321.",
            "ocr_variants": ["terminado en +++ 321."] * 3,
            "ocr_consensus_text": "terminado en +++ 321.",
            "text_lineage": {"source_tokens": ["+++"], "source_token_regions": [dot_region]},
        }],
        "reader_uncertainties": [
            {"element_id": "T-MASK", "code": "OCR_DISAGREEMENT"},
            {"element_id": "OTHER", "code": "OCR_DISAGREEMENT"},
        ],
    }
    normalized = subject.apply_pixel_mask_normalization(candidate, dot_image)
    target = normalized["elements"][0]
    checks["candidate_visible_text_corrected"] = target.get("visible_text") == "terminado en ••• 321."
    checks["normalization_trace_present"] = bool(target.get("pixel_glyph_normalizations"))
    checks["target_uncertainty_removed_after_convergence"] = not any(
        item.get("element_id") == "T-MASK" and item.get("code") == "OCR_DISAGREEMENT"
        for item in normalized.get("reader_uncertainties", [])
    )
    checks["unrelated_uncertainty_preserved"] = any(
        item.get("element_id") == "OTHER" and item.get("code") == "OCR_DISAGREEMENT"
        for item in normalized.get("reader_uncertainties", [])
    )

    # Technical causal cases measured on 10 governed SOURCE_IMAGE records.
    # No authentic P0-5 human adjudication is claimed.
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
                t_attempt("psm11-input", "tucorreoOemail.com", valid=True, stable=True),
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
                t_attempt("psm6-form", "1234 5678 9012 3456", valid=False, stable=False),
                t_attempt("psm11-form", "1234 5678 9012 3456", valid=False, stable=False),
                t_attempt("psm12-form", "1234 5678 9012 3456", valid=False, stable=False),
            ],
            "challenger_allowed": True,
        },
        "cand08_sep_amount": {
            "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 211.19",
            "targeted_attempts": [
                t_attempt("psm6-up2", "S/ 211.19", valid=False),
                t_attempt("psm7-up2", "S/ 211.19", valid=False),
                t_attempt("psm11-up2", "S/ 211.19", valid=False),
            ],
            "challenger_allowed": True,
        },
        "cand10_igv": {
            "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 1",
            "targeted_attempts": [
                t_attempt("psm6-up3", "S/ 18", valid=True, stable=True),
                t_attempt("psm7-up3", "S/ 18", valid=True, stable=True),
                t_attempt("psm11-up3", "S/ 18", valid=True, stable=True),
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
        "cand10_igv": "PADDLE_REQUIRED",
    }
    for name, observation in source_bound.items():
        checks[f"route_{name}"] = route(observation).get("decision") == expected[name]

    checks["two_real_persistent_paddle_triggers"] = sum(
        1 for observation in source_bound.values() if route(observation).get("decision") == "PADDLE_REQUIRED"
    ) == 2

    # Caller-declared validity/stability/confidence/persistence must not bypass.
    checks["declared_valid_and_stable_invalid_email_still_routes_paddle"] = (
        route(source_bound["s03_email"]).get("decision") == "PADDLE_REQUIRED"
    )
    checks["duplicate_variant_cannot_fake_consensus"] = route({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("same", "a@b.com", valid=True, stable=True),
            t_attempt("same", "a@b.com", valid=True, stable=True),
        ],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["single_valid_variant_cannot_stop_before_paddle"] = route({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("one", "a@b.com", valid=True, stable=True),
            t_attempt("two", "still-bad", valid=True, stable=True),
        ],
        "challenger_allowed": True,
    }).get("decision") == "PADDLE_REQUIRED"
    checks["two_distinct_valid_variants_create_consensus"] = route({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("one", "a@b.com", valid=False, stable=False),
            t_attempt("two", "a@b.com", valid=False, stable=False),
        ],
        "challenger_allowed": True,
    }).get("decision") == "TARGETED_TESSERACT_ACCEPT"
    checks["untraceable_attempts_do_not_count"] = route({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18",
        "targeted_attempts": [
            {"engine_family": "TESSERACT", "text": "S/ 18.00", "valid": True, "stable": True},
            {"engine_family": "TESSERACT", "text": "S/ 18.00", "valid": True, "stable": True},
        ],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["caller_persistent_flag_cannot_authorize_single_variant"] = route({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18",
        "persistent_invariant_failure": True,
        "targeted_attempts": [t_attempt("only", "S/ 18", valid=True, stable=True)],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["caller_persistent_false_cannot_suppress_derived_failure"] = route({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18",
        "persistent_invariant_failure": False,
        "targeted_attempts": [
            t_attempt("a", "S/ 18", valid=True, stable=True),
            t_attempt("b", "S/ 18.1", valid=True, stable=True),
        ],
        "challenger_allowed": True,
    }).get("decision") == "PADDLE_REQUIRED"
    checks["invalid_high_confidence_cannot_bypass"] = route({
        "materiality": "TEXT", "kind": "email", "baseline_text": "aXb.com", "baseline_confidence": 0.99999,
        "targeted_attempts": [
            t_attempt("one", "aXb.com", valid=True, stable=True, confidence=0.99999),
            t_attempt("two", "aXb.com", valid=True, stable=True, confidence=0.99999),
        ],
        "challenger_allowed": True,
    }).get("decision") == "PADDLE_REQUIRED"

    checks["valid_baseline_preserved"] = route({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 10.00", "baseline_valid": False,
        "targeted_attempts": [], "challenger_allowed": True,
    }).get("decision") == "BASELINE_PRESERVED"
    checks["valid_vs_valid_targeted_disagreement_abstains"] = route({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 10.00",
        "targeted_attempts": [
            t_attempt("one", "S/ 100.00"), t_attempt("two", "S/ 100.00")
        ],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW_VALID_DISAGREEMENT"
    checks["unstructured_text_cannot_self_validate_or_invoke_paddle"] = route({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "garbled",
        "targeted_attempts": [t_attempt("one", "different words"), t_attempt("two", "different words")],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["visible_truncation_never_completed"] = route({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "Política de priv...",
        "visible_truncated": True, "targeted_attempts": [t_attempt("one", "Política de privacidad"), t_attempt("two", "Política de privacidad")],
        "challenger_allowed": True,
    }).get("decision") == "VISIBLE_ONLY_NO_COMPLETION"
    checks["pixel_correction_requires_proof"] = route({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "+++",
        "structural_resolution_proven": False,
        "structural_resolution_code": "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"
    checks["nontext_never_invokes_paddle"] = route({
        "materiality": "NON_TEXT_ICON", "baseline_text": "E",
        "targeted_attempts": [t_attempt("one", "E"), t_attempt("two", "E")],
        "challenger_allowed": True,
    }).get("invoke_paddle") is False
    checks["successful_targeted_consensus_stops_paddle"] = route(source_bound["cand07_card"]).get("invoke_paddle") is False
    checks["persistent_email_failure_authorizes_paddle"] = route(source_bound["s03_email"]).get("invoke_paddle") is True
    checks["persistent_igv_failure_authorizes_paddle"] = route(source_bound["cand10_igv"]).get("invoke_paddle") is True

    # Paddle reconciliation is synthetic contract testing only; no real Paddle result is claimed here.
    synthetic_paddle_good = [
        p_attempt("run-1", "S/ 18.00", valid=False, stable=False, confidence=0.01),
        p_attempt("run-2", "S/ 18.00", valid=False, stable=False, confidence=0.99),
    ]
    synthetic_fix = router.reconcile_paddle(source_bound["cand10_igv"], synthetic_paddle_good)
    checks["two_traceable_valid_paddle_variants_can_repair"] = (
        synthetic_fix.get("decision") == "PADDLE_STRUCTURAL_CORRECTION"
        and synthetic_fix.get("resolved") is True
        and synthetic_fix.get("text") == "S/ 18.00"
    )
    checks["one_paddle_variant_cannot_claim_stability"] = (
        router.reconcile_paddle(source_bound["cand10_igv"], [p_attempt("only", "S/ 18.00", stable=True)]).get("decision")
        == "NEEDS_REVIEW"
    )
    checks["duplicate_paddle_variant_cannot_claim_stability"] = (
        router.reconcile_paddle(source_bound["cand10_igv"], [
            p_attempt("same", "S/ 18.00", stable=True), p_attempt("same", "S/ 18.00", stable=True)
        ]).get("decision") == "NEEDS_REVIEW"
    )
    checks["two_different_valid_paddle_values_abstain"] = (
        router.reconcile_paddle(source_bound["cand10_igv"], [
            p_attempt("a", "S/ 18.00"), p_attempt("b", "S/ 19.00")
        ]).get("decision") == "NEEDS_REVIEW"
    )
    checks["invalid_paddle_outputs_rejected"] = (
        router.reconcile_paddle(source_bound["cand10_igv"], [
            p_attempt("a", "S/ 18", valid=True, stable=True), p_attempt("b", "S/ 18", valid=True, stable=True)
        ]).get("decision") == "NEEDS_REVIEW"
    )
    checks["paddle_not_authorized_when_tesseract_consensus_succeeds"] = (
        router.reconcile_paddle(source_bound["cand07_card"], [
            p_attempt("a", "1234 5678 9012 3456"), p_attempt("b", "1234 5678 9012 3456")
        ]).get("decision") == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"
    )

    implementation = (SCRIPT_ROOT / "p0_multiscreen_structural_generalization_v1.py").read_text(encoding="utf-8")
    router_source = (CONTRACT_ROOT / "P0_SELECTIVE_OCR_ROUTER_V2.py").read_text(encoding="utf-8")
    forbidden_literals = [
        "WhatsApp", "321", "Paso 2", "Confirma tu celular",
        "9f824b1d357ea0dd156046dfc6a410fe92f1942bb225223208602abbb7fb6560",
    ]
    checks["implementation_has_no_screen_literals"] = not any(value in implementation for value in forbidden_literals)
    checks["router_has_no_source_sha_or_coordinates"] = not any(token in router_source for token in [
        "9f824b1d357ea0dd156046dfc6a410fe92f1942bb225223208602abbb7fb6560",
        "af332f828d4c0e39ac36fc9fa9459062d59ee52cad9400349ba7bb3e2c0e97df", "1536", "1844",
    ])
    checks["router_ignores_confidence"] = ('get("confidence")' not in router_source and "['confidence']" not in router_source)
    checks["router_ignores_declared_valid_stable_persistent"] = all([
        checks["declared_valid_and_stable_invalid_email_still_routes_paddle"],
        checks["caller_persistent_flag_cannot_authorize_single_variant"],
        checks["caller_persistent_false_cannot_suppress_derived_failure"],
        checks["invalid_paddle_outputs_rejected"],
    ])
    checks["no_interaction_inference"] = "interaction_functions_confirmed\": 0" in implementation

    failed = sorted(name for name, passed in checks.items() if not passed)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION",
        "checks": checks,
        "check_count": len(checks),
        "failed": failed,
        "source_bound_technical_cases": len(source_bound),
        "governed_source_images_available": 10,
        "persistent_paddle_required_cases": 2,
        "persistent_paddle_required_case_names": ["s03_email", "cand10_igv"],
        "real_paddle_outcome_for_new_cases": "NOT_EXECUTED",
        "routing_order": [
            "STRUCTURAL_OR_NON_TEXT",
            "TARGETED_TESSERACT_REPEATED_CONSENSUS",
            "PADDLE_ONLY_AFTER_REPEATED_TARGETED_FAILURE",
            "ABSTAIN_OR_HUMAN_REVIEW",
        ],
        "caller_validity_stability_persistence_flags_authoritative": False,
        "unstructured_text_autocorrection_allowed": False,
        "paddle_runtime_promoted": False,
        "synthetic_and_source_bound_technical_regression_only": True,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        fail("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION", ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
