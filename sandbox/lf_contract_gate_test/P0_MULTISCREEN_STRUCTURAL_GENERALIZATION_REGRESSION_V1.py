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


def decision(observation: dict) -> str:
    return str(router.route_observation(observation).get("decision"))


def main() -> int:
    checks: dict[str, bool] = {}

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

    source_bound = {
        "s02_mask": {
            "materiality": "TEXT", "kind": "generic_text", "baseline_text": "+++ 321",
            "structural_resolution_proven": True,
            "structural_resolution_code": "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
            "challenger_allowed": True,
        },
        "s02_cells": {
            "materiality": "NON_TEXT_CONTROL", "kind": "generic_text", "baseline_text": "HOOO0O",
            "persistent_invariant_failure": True, "challenger_allowed": True,
        },
        "s03_email": {
            "materiality": "TEXT", "kind": "email", "baseline_text": "",
            "targeted_attempts": [{
                "engine_family": "TESSERACT", "text": "tucorreo@email.com", "stable": True,
                "valid": False,
            }],
            "persistent_invariant_failure": False, "challenger_allowed": True,
        },
        "cand06_qr": {
            "materiality": "NON_TEXT_QR", "kind": "generic_text", "baseline_text": "cn ES Ea E paga pe",
            "persistent_invariant_failure": True, "challenger_allowed": True,
        },
        "cand07_card": {
            "materiality": "TEXT", "kind": "card_number", "baseline_text": "4 5 5 6 12 56",
            "targeted_attempts": [{
                "engine_family": "TESSERACT", "text": "1234 5678 9012 3456", "stable": True,
                "valid": False,
            }],
            "persistent_invariant_failure": False, "challenger_allowed": True,
        },
        "cand08_sep_amount": {
            "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 211.19",
            "targeted_attempts": [{
                "engine_family": "TESSERACT", "text": "S/ 211.19", "stable": True, "valid": False,
            }],
            "persistent_invariant_failure": True, "challenger_allowed": True,
        },
        "cand10_igv": {
            "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 1",
            "targeted_attempts": [
                {"engine_family": "TESSERACT", "text": "S/ 18", "stable": True, "valid": True},
                {"engine_family": "TESSERACT", "text": "S/ 18.", "stable": True, "valid": True},
                {"engine_family": "TESSERACT", "text": "S/ 18.1", "stable": True, "valid": True},
            ],
            "persistent_invariant_failure": True, "challenger_allowed": True,
        },
    }
    expected = {
        "s02_mask": "STRUCTURAL_PIXEL_RESOLVED",
        "s02_cells": "DISCARD_NON_TEXT_OCR",
        "s03_email": "TARGETED_TESSERACT_ACCEPT",
        "cand06_qr": "DISCARD_NON_TEXT_OCR",
        "cand07_card": "TARGETED_TESSERACT_ACCEPT",
        "cand08_sep_amount": "TARGETED_TESSERACT_ACCEPT",
        "cand10_igv": "PADDLE_REQUIRED",
    }
    for name, observation in source_bound.items():
        checks[f"route_{name}"] = decision(observation) == expected[name]

    checks["valid_baseline_preserved"] = decision({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 10.00",
        "baseline_valid": False,
        "persistent_invariant_failure": False, "challenger_allowed": True,
    }) == "BASELINE_PRESERVED"

    checks["valid_vs_valid_disagreement_abstains"] = decision({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 10.00",
        "targeted_attempts": [{"engine_family": "TESSERACT", "text": "S/ 100.00", "stable": True, "valid": False}],
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "NEEDS_REVIEW_VALID_DISAGREEMENT"

    checks["declared_target_valid_cannot_bypass_machine_validation"] = decision({
        "materiality": "TEXT", "kind": "email", "baseline_text": "aXb.com",
        "targeted_attempts": [{
            "engine_family": "TESSERACT", "text": "still-not-an-email", "stable": True,
            "valid": True, "confidence": 0.99999,
        }],
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "PADDLE_REQUIRED"

    checks["declared_baseline_valid_cannot_bypass_machine_validation"] = decision({
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18", "baseline_valid": True,
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "PADDLE_REQUIRED"

    checks["unstructured_text_cannot_self_validate_or_invoke_paddle"] = decision({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "garbled",
        "targeted_attempts": [{"engine_family": "TESSERACT", "text": "different words", "stable": True, "valid": True}],
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "NEEDS_REVIEW"

    checks["invalid_high_confidence_cannot_bypass"] = decision({
        "materiality": "TEXT", "kind": "email", "baseline_text": "aXb.com",
        "baseline_confidence": 0.9999,
        "targeted_attempts": [{
            "engine_family": "TESSERACT", "text": "aXb.com", "stable": True,
            "valid": True, "confidence": 0.99999,
        }],
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "PADDLE_REQUIRED"

    checks["visible_truncation_never_completed"] = decision({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "Política de priv...",
        "visible_truncated": True, "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "VISIBLE_ONLY_NO_COMPLETION"

    checks["pixel_correction_requires_proof_and_no_unstructured_paddle"] = decision({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "+++",
        "structural_resolution_proven": False,
        "structural_resolution_code": "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }) == "NEEDS_REVIEW"

    checks["nontext_never_invokes_paddle"] = router.route_observation({
        "materiality": "NON_TEXT_ICON", "baseline_text": "E",
        "persistent_invariant_failure": True, "challenger_allowed": True,
    }).get("invoke_paddle") is False
    checks["targeted_tesseract_stops_paddle"] = router.route_observation(source_bound["s03_email"]).get("invoke_paddle") is False
    checks["persistent_failure_authorizes_paddle_only_after_crop"] = router.route_observation(source_bound["cand10_igv"]).get("invoke_paddle") is True

    paddle_fix = router.reconcile_paddle(source_bound["cand10_igv"], "S/ 18.00", stable=True)
    checks["paddle_structural_correction_only_after_authorized_route"] = (
        paddle_fix.get("decision") == "PADDLE_STRUCTURAL_CORRECTION"
        and paddle_fix.get("resolved") is True
        and paddle_fix.get("text") == "S/ 18.00"
    )
    checks["paddle_invalid_output_rejected_by_internal_validator"] = (
        router.reconcile_paddle(source_bound["cand10_igv"], "S/ 18", stable=True).get("decision") == "NEEDS_REVIEW"
    )
    checks["paddle_not_authorized_when_tesseract_crop_succeeds"] = (
        router.reconcile_paddle(source_bound["s03_email"], "tucorreo@email.com", stable=True).get("decision")
        == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"
    )
    checks["unstable_paddle_abstains"] = (
        router.reconcile_paddle(source_bound["cand10_igv"], "S/ 18.00", stable=False).get("decision") == "NEEDS_REVIEW"
    )

    both_valid = {
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 10.00",
        "targeted_attempts": [], "persistent_invariant_failure": True, "challenger_allowed": True,
    }
    checks["both_valid_cross_engine_disagreement_preserves_baseline"] = (
        router.reconcile_paddle(both_valid, "S/ 11.00", stable=True).get("decision")
        == "BASELINE_PRESERVED_DISAGREEMENT"
    )

    implementation_path = SCRIPT_ROOT / "p0_multiscreen_structural_generalization_v1.py"
    implementation = implementation_path.read_text(encoding="utf-8")
    router_implementation = (CONTRACT_ROOT / "P0_SELECTIVE_OCR_ROUTER_V2.py").read_text(encoding="utf-8")
    forbidden_literals = [
        "WhatsApp", "321", "Paso 2", "Confirma tu celular",
        "9f824b1d357ea0dd156046dfc6a410fe92f1942bb225223208602abbb7fb6560",
    ]
    checks["implementation_has_no_screen_literals"] = not any(value in implementation for value in forbidden_literals)
    checks["router_has_no_source_sha_or_coordinates"] = not any(
        token in router_implementation for token in [
            "9f824b1d357ea0dd156046dfc6a410fe92f1942bb225223208602abbb7fb6560",
            "af332f828d4c0e39ac36fc9fa9459062d59ee52cad9400349ba7bb3e2c0e97df", "1536", "1844",
        ]
    )
    checks["router_ignores_confidence"] = ('get("confidence")' not in router_implementation and "['confidence']" not in router_implementation)
    # Behavioral proof is authoritative; do not depend on brittle source-string matching.
    checks["router_recomputes_validity"] = (
        checks["declared_target_valid_cannot_bypass_machine_validation"]
        and checks["declared_baseline_valid_cannot_bypass_machine_validation"]
        and checks["paddle_invalid_output_rejected_by_internal_validator"]
        and checks["valid_baseline_preserved"]
    )
    checks["no_interaction_inference"] = "interaction_functions_confirmed\": 0" in implementation

    failed = sorted(name for name, passed in checks.items() if not passed)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION",
        "checks": checks,
        "check_count": len(checks),
        "failed": failed,
        "source_bound_technical_cases": len(source_bound),
        "governed_source_images_available": 10,
        "routing_order": [
            "STRUCTURAL_OR_NON_TEXT", "TARGETED_TESSERACT",
            "PADDLE_ONLY_FOR_PERSISTENT_MACHINE_FAILURE", "ABSTAIN_OR_HUMAN_REVIEW",
        ],
        "caller_validity_flags_authoritative": False,
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
