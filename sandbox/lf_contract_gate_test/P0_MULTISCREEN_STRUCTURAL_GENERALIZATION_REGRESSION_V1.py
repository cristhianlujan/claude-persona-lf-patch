#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPO_ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPT_ROOT))

import p0_multiscreen_structural_generalization_v1 as subject


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
        "elements": [
            {
                "element_id": "T-MASK",
                "element_type": "TEXT",
                "visible_text": "terminado en +++ 321.",
                "ocr_variants": ["terminado en +++ 321.", "terminado en +++ 321.", "terminado en +++ 321."],
                "ocr_consensus_text": "terminado en +++ 321.",
                "text_lineage": {
                    "source_tokens": ["+++"],
                    "source_token_regions": [dot_region],
                },
            }
        ],
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

    implementation_path = SCRIPT_ROOT / "p0_multiscreen_structural_generalization_v1.py"
    implementation = implementation_path.read_text(encoding="utf-8")
    forbidden_literals = [
        "WhatsApp",
        "321",
        "Paso 2",
        "Confirma tu celular",
        "9f824b1d357ea0dd156046dfc6a410fe92f1942bb225223208602abbb7fb6560",
    ]
    checks["implementation_has_no_screen_literals"] = not any(value in implementation for value in forbidden_literals)
    checks["no_interaction_inference"] = "interaction_functions_confirmed\": 0" in implementation

    failed = sorted(name for name, passed in checks.items() if not passed)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION",
        "checks": checks,
        "check_count": len(checks),
        "failed": failed,
        "synthetic_regression_only": True,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "runtime_promoted_models": False,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        fail("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION", ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
