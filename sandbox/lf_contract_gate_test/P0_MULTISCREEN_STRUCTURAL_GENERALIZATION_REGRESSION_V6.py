#!/usr/bin/env python3
"""Source-bound regression for fail-closed masked structured values.

The real non-holdout source shows a partially obscured email. Tesseract can
stably render the hidden bullets as repeated asterisks, which V3's broad email
syntax accepted. V6 proves that obscuration evidence now blocks exact truth and
Paddle reconstruction while preserving ordinary structured values.
"""
from __future__ import annotations

import base64
import hashlib
import json
import subprocess
import tempfile
import zlib
from pathlib import Path

import numpy as np

import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V5 as v5
import P0_SELECTIVE_OCR_ROUTER_V4 as router
from P0_CROP_COMPLETENESS_GUARD_V1 import text_crop_has_clear_margin

ROOT = Path(__file__).resolve().parent
FIXTURE = ROOT / "evidence" / "P0_EXITO_MASKED_EMAIL_GRAY_ZLIB_V1.b64"
GOVERNED_SOURCE_DRIVE_ID = "1WMGmlvpV1KD9BjFFFirvdCu1I95_yL8r"
GOVERNED_SOURCE_SHA256 = "bf0f3d174f7a8257a1772d9cd9430e98b287fa661d3088dd85d833f49f41ae52"
SOURCE_DIMENSIONS = (853, 1844)
SOURCE_TEXT_ROI_XYXY = [423, 610, 630, 640]
FIXTURE_DIMENSIONS = (207, 30)
FIXTURE_RAW_LEN = 6210
FIXTURE_RAW_SHA256 = "616f718de2aca0ce736b308c5c49958487d7d3de06d1091a2751e97734e105a4"


def load_fixture() -> tuple[np.ndarray, str]:
    encoded = FIXTURE.read_text(encoding="ascii").strip()
    try:
        raw = zlib.decompress(base64.b64decode(encoded, validate=True))
    except Exception as exc:
        raise SystemExit(f"FAIL_MASKED_EMAIL_FIXTURE_DECODE:{type(exc).__name__}") from exc
    if len(raw) != FIXTURE_RAW_LEN:
        raise SystemExit(f"FAIL_MASKED_EMAIL_FIXTURE_RAW_LENGTH:{len(raw)}")
    digest = hashlib.sha256(raw).hexdigest()
    if digest != FIXTURE_RAW_SHA256:
        raise SystemExit(f"FAIL_MASKED_EMAIL_FIXTURE_RAW_SHA:{digest}")
    width, height = FIXTURE_DIMENSIONS
    image = np.frombuffer(raw, dtype=np.uint8).reshape(height, width).copy()
    return image, digest


def write_pgm(image: np.ndarray, path: Path) -> None:
    height, width = image.shape
    with path.open("w", encoding="ascii", newline="\n") as handle:
        handle.write(f"P2\n{width} {height}\n255\n")
        for row in image:
            handle.write(" ".join(str(int(value)) for value in row) + "\n")


def ocr(path: Path, profile: str, psm: int) -> str:
    run = subprocess.run(
        ["tesseract", str(path), "stdout", "-l", profile, "--psm", str(psm)],
        capture_output=True,
        text=True,
        check=False,
    )
    if run.returncode != 0:
        raise SystemExit(f"FAIL_MASKED_EMAIL_TESSERACT:{profile}:psm{psm}:{run.stderr.strip()}")
    return " ".join(run.stdout.strip().split())


def t_attempt(variant_id: str, text: str, profile: str) -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": profile,
    }


def p_attempt(variant_id: str, text: str) -> dict:
    return {"engine_family": "PADDLE", "variant_id": variant_id, "text": text}


def main() -> int:
    # Preserve every V5 invariant before adding the new real-source attack.
    if v5.main() != 0:
        raise SystemExit("FAIL_V5_PREREQUISITE")

    checks: dict[str, bool] = {}
    fixture, raw_sha = load_fixture()
    checks["fixture_sha_exact"] = raw_sha == FIXTURE_RAW_SHA256
    checks["fixture_dimensions_exact"] = (fixture.shape[1], fixture.shape[0]) == FIXTURE_DIMENSIONS
    checks["source_roi_dimensions_exact"] = (
        SOURCE_TEXT_ROI_XYXY[2] - SOURCE_TEXT_ROI_XYXY[0],
        SOURCE_TEXT_ROI_XYXY[3] - SOURCE_TEXT_ROI_XYXY[1],
    ) == FIXTURE_DIMENSIONS
    checks["text_roi_crop_complete"] = text_crop_has_clear_margin(fixture, margin_px=3)

    with tempfile.TemporaryDirectory(prefix="p0-masked-email-") as tmp:
        pgm = Path(tmp) / "masked_email.pgm"
        write_pgm(fixture, pgm)
        observed = {
            "eng_psm6": ocr(pgm, "eng", 6),
            "eng_psm7": ocr(pgm, "eng", 7),
        }

    checks["two_tesseract_variants_agree"] = observed["eng_psm6"] == observed["eng_psm7"]
    checks["observed_mask_detected_psm6"] = router.is_masked_structured_text(observed["eng_psm6"])
    checks["observed_mask_detected_psm7"] = router.is_masked_structured_text(observed["eng_psm7"])
    checks["observed_mask_not_machine_valid"] = not router.validate_text("email", observed["eng_psm6"])

    masked = {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": "",
        "targeted_attempts": [
            t_attempt("eng-psm6", observed["eng_psm6"], "eng"),
            t_attempt("eng-psm7", observed["eng_psm7"], "eng"),
        ],
        "challenger_allowed": True,
    }
    route = router.route_observation(masked)
    checks["masked_route_fail_closed"] = route.get("decision") == "VISIBLE_MASKED_NO_COMPLETION"
    checks["masked_route_unresolved"] = route.get("resolved") is False
    checks["masked_route_no_paddle"] = route.get("invoke_paddle") is False

    paddle = router.reconcile_paddle(
        masked,
        [p_attempt("p1", "invented@example.com"), p_attempt("p2", "invented@example.com")],
    )
    checks["paddle_cannot_reconstruct_hidden_value"] = (
        paddle.get("decision") == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"
        and paddle.get("resolved") is False
    )

    checks["visible_bullet_mask_invalid"] = not router.validate_text("email", "ju••••@gmail.com")
    checks["repeated_star_mask_invalid"] = not router.validate_text("email", "jus***@gmail.com")
    checks["normal_email_preserved"] = router.validate_text("email", "tucorreo@email.com")
    checks["plus_tag_email_preserved"] = router.validate_text("email", "user+tag@example.com")
    checks["single_star_localpart_not_overblocked"] = router.validate_text("email", "ab*c@example.com")
    checks["two_stars_not_overblocked"] = router.validate_text("email", "ab**c@example.com")
    checks["middle_dot_not_inferred_as_mask"] = not router.is_masked_structured_text("ab·cd@example.com")
    checks["currency_validator_preserved"] = router.validate_text("currency", "S/ 2,111.92")

    failed = sorted(name for name, ok in checks.items() if not ok)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V6" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V6",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "governed_source_drive_id": GOVERNED_SOURCE_DRIVE_ID,
        "governed_source_sha256": GOVERNED_SOURCE_SHA256,
        "source_dimensions": SOURCE_DIMENSIONS,
        "source_text_roi_xyxy": SOURCE_TEXT_ROI_XYXY,
        "fixture_raw_gray_sha256": raw_sha,
        "tesseract_outputs": observed,
        "root_cause": "MASKED_STRUCTURED_VALUE_FALSE_POSITIVE",
        "decision_after": route.get("decision"),
        "false_positive_before": 1,
        "false_positive_after": 0 if not failed else None,
        "paddle_required": 0,
        "needs_review": 1,
        "human_review_required": True,
        "new_real_sources": 1,
        "new_families": 1,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
        "sealed_holdout_accessed": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V6:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
