#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

import cv2
import numpy as np

import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V4 as v4
import P0_SELECTIVE_OCR_ROUTER_V3 as router
from P0_CROP_COMPLETENESS_GUARD_V1 import text_crop_has_clear_margin

EXPECTED_EMAIL = "tucorreo@email.com"
TEXT_ROI_RELATIVE_XYXY = [15, 40, 312, 78]
TEXT_ROI_SOURCE_XYXY = [120, 1020, 417, 1058]
TEXT_ROI_RAW_SHA256 = "7ad394603d697d4db42fe625261472cb255f7e0bf2424cbb51258cd3abca9249"


def t_attempt(variant_id: str, text: str, language_profile: str = "", **extra: object) -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": language_profile,
        **extra,
    }


def p_attempt(variant_id: str, text: str) -> dict:
    return {"engine_family": "PADDLE", "variant_id": variant_id, "text": text}


def main() -> int:
    checks: dict[str, bool] = {}

    cells = v4.subject.detect_segmented_input_cells(v4.draw_cells(6))
    checks["six_cells_detected"] = len(cells) == 6
    checks["one_segmented_group"] = len({cell.get("repeated_control_group_id") for cell in cells}) == 1
    checks["three_cells_rejected"] = v4.subject.detect_segmented_input_cells(v4.draw_cells(3)) == []
    checks["misaligned_cells_rejected"] = v4.subject.detect_segmented_input_cells(v4.draw_cells(6, True)) == []

    clear = np.full((40, 120), 255, dtype=np.uint8)
    cv2.putText(clear, "18.00", (18, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65, 0, 1, cv2.LINE_AA)
    checks["complete_crop_eligible"] = text_crop_has_clear_margin(clear, margin_px=2)
    checks["clipped_crop_rejected"] = not text_crop_has_clear_margin(clear[:, :70].copy(), margin_px=2)

    fixture, part_names, raw_sha = v4.load_fixture()
    checks["fixture_sha_exact"] = raw_sha == v4.EXPECTED_RAW_SHA256
    checks["fixture_dimensions_exact"] = (fixture.shape[1], fixture.shape[0]) == v4.EXPECTED_DIMENSIONS

    x1, y1, x2, y2 = TEXT_ROI_RELATIVE_XYXY
    text_fixture = fixture[y1:y2, x1:x2].copy()
    text_sha = hashlib.sha256(text_fixture.tobytes()).hexdigest()
    checks["text_roi_sha_exact"] = text_sha == TEXT_ROI_RAW_SHA256
    checks["text_roi_dimensions_exact"] = (text_fixture.shape[1], text_fixture.shape[0]) == (297, 38)
    checks["text_roi_crop_complete"] = text_crop_has_clear_margin(text_fixture, margin_px=3)

    installed = v4.languages()
    checks["spa_available"] = "spa" in installed
    checks["eng_available"] = "eng" in installed

    with tempfile.TemporaryDirectory(prefix="p0-s03-email-") as tmp:
        pgm = Path(tmp) / "s03_email_text_roi.pgm"
        v4.write_pgm(text_fixture, pgm)
        observed = {
            "spa": v4.ocr(pgm, "spa"),
            "eng": v4.ocr(pgm, "eng"),
            "spa+eng": v4.ocr(pgm, "spa+eng"),
        }

    checks["spa_machine_invalid"] = not router.validate_text("email", observed["spa"])
    checks["eng_exact"] = observed["eng"] == EXPECTED_EMAIL
    checks["spa_eng_exact"] = observed["spa+eng"] == EXPECTED_EMAIL

    s03 = {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": "",
        "targeted_attempts": [
            t_attempt("psm7-spa", observed["spa"], "spa"),
            t_attempt("psm7-eng", observed["eng"], "eng"),
            t_attempt("psm7-spa-eng", observed["spa+eng"], "spa+eng"),
        ],
        "challenger_allowed": True,
    }
    route = router.route_observation(s03)
    checks["s03_tesseract_accept"] = route.get("decision") == "TARGETED_TESSERACT_ACCEPT"
    checks["s03_exact_text"] = route.get("text") == EXPECTED_EMAIL
    checks["s03_no_paddle"] = route.get("invoke_paddle") is False

    same_profile = {
        "materiality": "TEXT", "kind": "email", "baseline_text": "",
        "targeted_attempts": [
            t_attempt("psm6", "bad-email", "spa", valid=True, stable=True, confidence=0.999),
            t_attempt("psm11", "still-bad", "spa", valid=True, stable=True, confidence=0.999),
        ],
        "challenger_allowed": True,
    }
    same_route = router.route_observation(same_profile)
    checks["same_profile_expands_before_paddle"] = (
        same_route.get("decision") == "TESSERACT_PROFILE_EXPANSION_REQUIRED"
        and same_route.get("invoke_paddle") is False
    )

    two_profile_failure = {
        "materiality": "TEXT", "kind": "email", "baseline_text": "",
        "targeted_attempts": [
            t_attempt("spa-a", "bad-email", "spa"),
            t_attempt("eng-a", "also-bad", "eng"),
        ],
        "challenger_allowed": True,
    }
    checks["two_profile_failure_can_reach_paddle"] = (
        router.route_observation(two_profile_failure).get("decision") == "PADDLE_REQUIRED"
    )

    duplicate = {
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("same", "a@b.com", "spa"),
            t_attempt("same", "a@b.com", "eng"),
        ],
        "challenger_allowed": True,
    }
    checks["duplicate_variant_no_consensus"] = router.route_observation(duplicate).get("decision") == "NEEDS_REVIEW"

    unstructured = {
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "garbled",
        "targeted_attempts": [t_attempt("a", "different", "spa"), t_attempt("b", "different", "eng")],
        "challenger_allowed": True,
    }
    checks["unstructured_not_autocorrected"] = router.route_observation(unstructured).get("decision") == "NEEDS_REVIEW"

    truncated = {
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "Política de priv...",
        "visible_truncated": True,
        "targeted_attempts": [
            t_attempt("a", "Política de privacidad", "spa"),
            t_attempt("b", "Política de privacidad", "eng"),
        ],
        "challenger_allowed": True,
    }
    checks["visible_truncation_not_completed"] = (
        router.route_observation(truncated).get("decision") == "VISIBLE_ONLY_NO_COMPLETION"
    )

    currency = {
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18",
        "targeted_attempts": [
            t_attempt("bad-a", "S/ 18", "spa"),
            t_attempt("bad-b", "S/ 18.1", "spa"),
        ],
        "challenger_allowed": True,
    }
    checks["currency_paddle_path_preserved"] = router.route_observation(currency).get("decision") == "PADDLE_REQUIRED"
    fixed = router.reconcile_paddle(currency, [p_attempt("a", "S/ 18.00"), p_attempt("b", "S/ 18.00")])
    checks["paddle_requires_repeated_valid_consensus"] = (
        fixed.get("decision") == "PADDLE_STRUCTURAL_CORRECTION" and fixed.get("text") == "S/ 18.00"
    )
    checks["paddle_not_authorized_after_s03_success"] = (
        router.reconcile_paddle(s03, [p_attempt("a", EXPECTED_EMAIL), p_attempt("b", EXPECTED_EMAIL)]).get("decision")
        == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"
    )

    failed = sorted(name for name, ok in checks.items() if not ok)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V5" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V5",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "governed_s03_source_sha256": v4.GOVERNED_SOURCE_SHA256,
        "source_container_roi_xyxy": v4.SOURCE_ROI_XYXY,
        "source_text_roi_xyxy": TEXT_ROI_SOURCE_XYXY,
        "fixture_part_names": part_names,
        "fixture_raw_gray_sha256": raw_sha,
        "text_roi_raw_gray_sha256": text_sha,
        "tesseract_profile_outputs": observed,
        "s03_email_route": route.get("decision"),
        "s03_email_resolved_text": route.get("text"),
        "persistent_paddle_required_cases": 0,
        "root_cause": "TESSERACT_LANGUAGE_PROFILE_SENSITIVITY",
        "paddle_executed_for_s03": False,
        "paddle_runtime_promoted": False,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V5:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
