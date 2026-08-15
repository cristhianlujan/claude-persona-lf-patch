#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent
SCRIPT_ROOT = ROOT.parents[1] / "story_creator_p0_visual" / "v1.1" / "scripts"
EVIDENCE = ROOT / "evidence"
PART_GLOB = "P0_S03_EMAIL_GRAY_ZLIB_V1.part*"
EXPECTED_PART_COUNT = 14
EXPECTED_B64_LEN = 12512
EXPECTED_RAW_LEN = 26000
EXPECTED_DIMENSIONS = (325, 80)
EXPECTED_RAW_SHA256 = "0dc0c40503bb45c3f821713d5c11f5fdb3daba5e9a0ba78c7d19c70607c18dd2"
GOVERNED_SOURCE_SHA256 = "af332f828d4c0e39ac36fc9fa9459062d59ee52cad9400349ba7bb3e2c0e97df"
SOURCE_ROI_XYXY = [105, 980, 430, 1060]
EXPECTED_EMAIL = "tucorreo@email.com"

sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(ROOT))

import p0_multiscreen_structural_generalization_v1 as subject
import P0_SELECTIVE_OCR_ROUTER_V3 as router
from P0_CROP_COMPLETENESS_GUARD_V1 import text_crop_has_clear_margin


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


def load_fixture() -> tuple[np.ndarray, list[str], str]:
    parts = sorted(EVIDENCE.glob(PART_GLOB))
    names = [path.name for path in parts]
    if len(parts) != EXPECTED_PART_COUNT:
        raise SystemExit(f"FAIL_EMAIL_FIXTURE_PART_COUNT:{len(parts)}")
    encoded = "".join(path.read_text(encoding="ascii").strip() for path in parts)
    if len(encoded) != EXPECTED_B64_LEN:
        raise SystemExit(f"FAIL_EMAIL_FIXTURE_B64_LENGTH:{len(encoded)}")
    try:
        raw = zlib.decompress(base64.b64decode(encoded, validate=True))
    except Exception as exc:
        raise SystemExit(f"FAIL_EMAIL_FIXTURE_DECODE:{type(exc).__name__}") from exc
    if len(raw) != EXPECTED_RAW_LEN:
        raise SystemExit(f"FAIL_EMAIL_FIXTURE_RAW_LENGTH:{len(raw)}")
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_RAW_SHA256:
        raise SystemExit(f"FAIL_EMAIL_FIXTURE_RAW_SHA:{digest}")
    width, height = EXPECTED_DIMENSIONS
    image = np.frombuffer(raw, dtype=np.uint8).reshape(height, width).copy()
    return image, names, digest


def write_pgm(image: np.ndarray, path: Path) -> None:
    height, width = image.shape
    with path.open("w", encoding="ascii", newline="\n") as handle:
        handle.write(f"P2\n{width} {height}\n255\n")
        for row in image:
            handle.write(" ".join(str(int(value)) for value in row) + "\n")


def languages() -> set[str]:
    run = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True, check=False)
    if run.returncode != 0:
        raise SystemExit("FAIL_TESSERACT_LANGUAGE_READBACK")
    return {
        line.strip()
        for line in run.stdout.splitlines()
        if line.strip() and not line.lower().startswith("list of available languages")
    }


def ocr(path: Path, profile: str) -> str:
    run = subprocess.run(
        ["tesseract", str(path), "stdout", "-l", profile, "--psm", "7"],
        capture_output=True,
        text=True,
        check=False,
    )
    if run.returncode != 0:
        raise SystemExit(f"FAIL_TESSERACT_PROFILE_EXECUTION:{profile}:{run.stderr.strip()}")
    return " ".join(run.stdout.strip().split())


def draw_cells(count: int, misaligned: bool = False) -> np.ndarray:
    image = np.full((260, 900, 3), 255, dtype=np.uint8)
    for index in range(count):
        x = 70 + index * 106
        y = 80 + (22 if misaligned and index % 2 else 0)
        cv2.rectangle(image, (x, y), (x + 74, y + 90), (0, 0, 0), 2)
    return image


def main() -> int:
    checks: dict[str, bool] = {}

    cells = subject.detect_segmented_input_cells(draw_cells(6))
    checks["six_cells_detected"] = len(cells) == 6
    checks["one_segmented_group"] = len({cell.get("repeated_control_group_id") for cell in cells}) == 1
    checks["three_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(3)) == []
    checks["misaligned_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(6, True)) == []

    clear = np.full((40, 120), 255, dtype=np.uint8)
    cv2.putText(clear, "18.00", (18, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65, 0, 1, cv2.LINE_AA)
    checks["complete_crop_eligible"] = text_crop_has_clear_margin(clear, margin_px=2)
    checks["clipped_crop_rejected"] = not text_crop_has_clear_margin(clear[:, :70].copy(), margin_px=2)

    fixture, part_names, raw_sha = load_fixture()
    checks["fixture_sha_exact"] = raw_sha == EXPECTED_RAW_SHA256
    checks["fixture_dimensions_exact"] = (fixture.shape[1], fixture.shape[0]) == EXPECTED_DIMENSIONS
    checks["fixture_crop_complete"] = text_crop_has_clear_margin(fixture, margin_px=2)

    installed = languages()
    checks["spa_available"] = "spa" in installed
    checks["eng_available"] = "eng" in installed

    with tempfile.TemporaryDirectory(prefix="p0-s03-email-") as tmp:
        pgm = Path(tmp) / "s03_email.pgm"
        write_pgm(fixture, pgm)
        observed = {
            "spa": ocr(pgm, "spa"),
            "eng": ocr(pgm, "eng"),
            "spa+eng": ocr(pgm, "spa+eng"),
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
    s03_route = router.route_observation(s03)
    checks["s03_tesseract_accept"] = s03_route.get("decision") == "TARGETED_TESSERACT_ACCEPT"
    checks["s03_exact_text"] = s03_route.get("text") == EXPECTED_EMAIL
    checks["s03_no_paddle"] = s03_route.get("invoke_paddle") is False

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
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V4" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V4",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "governed_s03_source_sha256": GOVERNED_SOURCE_SHA256,
        "source_roi_xyxy": SOURCE_ROI_XYXY,
        "fixture_part_names": part_names,
        "fixture_raw_gray_sha256": raw_sha,
        "tesseract_profile_outputs": observed,
        "s03_email_route": s03_route.get("decision"),
        "s03_email_resolved_text": s03_route.get("text"),
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
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V4:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
