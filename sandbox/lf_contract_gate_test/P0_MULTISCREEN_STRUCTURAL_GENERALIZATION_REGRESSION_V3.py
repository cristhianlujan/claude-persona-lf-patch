#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPO_ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
CONTRACT_ROOT = Path(__file__).resolve().parent
FIXTURE = CONTRACT_ROOT / "evidence" / "P0_S03_EMAIL_CROP_20260815.png"
FIXTURE_SHA256 = "10f9a45e7bfaf898460ae8d7424c9127bfd374daf6a7cd77bb2bd659d979b4fb"
FIXTURE_DIMENSIONS = (325, 80)
EXPECTED_EMAIL = "tucorreo@email.com"
GOVERNED_S03_SOURCE_SHA256 = "af332f828d4c0e39ac36fc9fa9459062d59ee52cad9400349ba7bb3e2c0e97df"

sys.path.insert(0, str(SCRIPT_ROOT))
sys.path.insert(0, str(CONTRACT_ROOT))

import p0_multiscreen_structural_generalization_v1 as subject
import P0_SELECTIVE_OCR_ROUTER_V3 as router
from P0_CROP_COMPLETENESS_GUARD_V1 import text_crop_has_clear_margin


def t_attempt(variant_id: str, text: str, language_profile: str = "", **untrusted: object) -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": language_profile,
        **untrusted,
    }


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


def tesseract_languages() -> set[str]:
    completed = subprocess.run(
        ["tesseract", "--list-langs"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit("FAIL_TESSERACT_LANGUAGE_READBACK")
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    return {line for line in lines if not line.lower().startswith("list of available languages")}


def run_tesseract(profile: str, psm: int = 7) -> str:
    completed = subprocess.run(
        ["tesseract", str(FIXTURE), "stdout", "-l", profile, "--psm", str(psm)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(f"FAIL_TESSERACT_PROFILE_EXECUTION:{profile}:{completed.stderr.strip()}")
    return " ".join(completed.stdout.strip().split())


def main() -> int:
    checks: dict[str, bool] = {}

    # Preserve structural regressions introduced in PR161/PR163.
    cells = subject.detect_segmented_input_cells(draw_cells(6))
    checks["six_cells_detected"] = len(cells) == 6
    checks["one_segmented_group"] = len({c.get("repeated_control_group_id") for c in cells}) == 1
    checks["three_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(3)) == []
    checks["misaligned_cells_rejected"] = subject.detect_segmented_input_cells(draw_cells(6, True)) == []

    dots, region = mask_image(False)
    pluses, plus_region = mask_image(True)
    checks["filled_dots_normalize"] = subject.normalize_repeated_mask_token(dots, region, "+++") == "•••"
    checks["real_plus_preserved"] = subject.normalize_repeated_mask_token(pluses, plus_region, "+++") is None

    clear = np.full((40, 120), 255, dtype=np.uint8)
    cv2.putText(clear, "18.00", (18, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.65, 0, 1, cv2.LINE_AA)
    clipped = clear[:, :70].copy()
    checks["clear_text_crop_eligible"] = text_crop_has_clear_margin(clear, margin_px=2)
    checks["edge_clipped_text_crop_rejected"] = not text_crop_has_clear_margin(clipped, margin_px=2)

    # Source-bound fixture derived byte-for-byte from governed S03 SOURCE_IMAGE.
    raw = FIXTURE.read_bytes()
    fixture_sha = hashlib.sha256(raw).hexdigest()
    fixture_image = cv2.imread(str(FIXTURE))
    checks["email_fixture_sha_exact"] = fixture_sha == FIXTURE_SHA256
    checks["email_fixture_decodes"] = fixture_image is not None
    checks["email_fixture_dimensions_exact"] = (
        fixture_image is not None
        and (fixture_image.shape[1], fixture_image.shape[0]) == FIXTURE_DIMENSIONS
    )
    checks["email_fixture_crop_complete"] = (
        fixture_image is not None
        and text_crop_has_clear_margin(cv2.cvtColor(fixture_image, cv2.COLOR_BGR2GRAY), margin_px=2)
    )

    languages = tesseract_languages()
    checks["tesseract_spa_available"] = "spa" in languages
    checks["tesseract_eng_available"] = "eng" in languages

    observed = {
        "spa": run_tesseract("spa", 7),
        "eng": run_tesseract("eng", 7),
        "spa+eng": run_tesseract("spa+eng", 7),
    }
    checks["spa_reproduces_machine_invalid_email"] = not router.validate_text("email", observed["spa"])
    checks["eng_recovers_exact_email"] = observed["eng"] == EXPECTED_EMAIL
    checks["spa_eng_recovers_exact_email"] = observed["spa+eng"] == EXPECTED_EMAIL

    s03_email = {
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
    s03_route = router.route_observation(s03_email)
    checks["s03_email_tesseract_accept"] = s03_route.get("decision") == "TARGETED_TESSERACT_ACCEPT"
    checks["s03_email_exact_text"] = s03_route.get("text") == EXPECTED_EMAIL
    checks["s03_email_does_not_invoke_paddle"] = s03_route.get("invoke_paddle") is False

    # Regression: repeated PSMs under one language profile do not prove that
    # same-family recovery space is exhausted for punctuation-sensitive email.
    same_profile_failure = {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": "",
        "targeted_attempts": [
            t_attempt("psm6", "bad-email", "spa", valid=True, stable=True, confidence=0.999),
            t_attempt("psm11", "still-bad", "spa", valid=True, stable=True, confidence=0.999),
        ],
        "challenger_allowed": True,
    }
    same_profile_route = router.route_observation(same_profile_failure)
    checks["same_profile_failure_requests_profile_expansion"] = (
        same_profile_route.get("decision") == "TESSERACT_PROFILE_EXPANSION_REQUIRED"
        and same_profile_route.get("invoke_paddle") is False
    )

    # Challenger remains reachable when two Tesseract language profiles have
    # both produced traceable machine-invalid results.
    two_profile_failure = {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": "",
        "targeted_attempts": [
            t_attempt("spa-a", "bad-email", "spa"),
            t_attempt("eng-a", "also-bad", "eng"),
        ],
        "challenger_allowed": True,
    }
    checks["two_profile_persistent_failure_can_reach_paddle"] = (
        router.route_observation(two_profile_failure).get("decision") == "PADDLE_REQUIRED"
    )

    checks["duplicate_variant_cannot_fake_consensus"] = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("same", "a@b.com", "spa"),
            t_attempt("same", "a@b.com", "eng"),
        ],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"

    checks["caller_valid_stable_confidence_cannot_bypass"] = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("one", "still-bad", "spa", valid=True, stable=True, confidence=0.99999),
            t_attempt("two", "also-bad", "eng", valid=True, stable=True, confidence=0.99999),
        ],
        "challenger_allowed": True,
    }).get("decision") == "PADDLE_REQUIRED"

    checks["two_distinct_valid_variants_create_consensus"] = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("one", "a@b.com", "spa"),
            t_attempt("two", "a@b.com", "eng"),
        ],
        "challenger_allowed": True,
    }).get("decision") == "TARGETED_TESSERACT_ACCEPT"

    checks["unstructured_text_never_self_validates"] = router.route_observation({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "garbled",
        "targeted_attempts": [t_attempt("one", "different", "spa"), t_attempt("two", "different", "eng")],
        "challenger_allowed": True,
    }).get("decision") == "NEEDS_REVIEW"

    checks["visible_truncation_never_completed"] = router.route_observation({
        "materiality": "TEXT", "kind": "generic_text", "baseline_text": "Política de priv...",
        "visible_truncated": True,
        "targeted_attempts": [t_attempt("one", "Política de privacidad", "spa"), t_attempt("two", "Política de privacidad", "eng")],
        "challenger_allowed": True,
    }).get("decision") == "VISIBLE_ONLY_NO_COMPLETION"

    # Non-email machine kinds keep the existing selective challenger contract.
    synthetic_paddle_target = {
        "materiality": "TEXT", "kind": "currency", "baseline_text": "S/ 18",
        "targeted_attempts": [t_attempt("bad-a", "S/ 18", "spa"), t_attempt("bad-b", "S/ 18.1", "spa")],
        "challenger_allowed": True,
    }
    checks["currency_target_still_authorizes_paddle"] = (
        router.route_observation(synthetic_paddle_target).get("decision") == "PADDLE_REQUIRED"
    )
    good = [p_attempt("run-1", "S/ 18.00"), p_attempt("run-2", "S/ 18.00")]
    fixed = router.reconcile_paddle(synthetic_paddle_target, good)
    checks["two_paddle_variants_can_repair_machine_failure"] = (
        fixed.get("decision") == "PADDLE_STRUCTURAL_CORRECTION" and fixed.get("text") == "S/ 18.00"
    )
    checks["one_paddle_variant_cannot_claim_stability"] = router.reconcile_paddle(
        synthetic_paddle_target, [p_attempt("only", "S/ 18.00")]
    ).get("decision") == "NEEDS_REVIEW"
    checks["different_valid_paddle_values_abstain"] = router.reconcile_paddle(
        synthetic_paddle_target, [p_attempt("a", "S/ 18.00"), p_attempt("b", "S/ 19.00")]
    ).get("decision") == "NEEDS_REVIEW"
    checks["paddle_not_authorized_after_s03_tesseract_success"] = router.reconcile_paddle(
        s03_email, [p_attempt("a", EXPECTED_EMAIL), p_attempt("b", EXPECTED_EMAIL)]
    ).get("decision") == "PADDLE_NOT_AUTHORIZED_FOR_OBSERVATION"

    failed = sorted(name for name, passed in checks.items() if not passed)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V3" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V3",
        "checks": checks,
        "check_count": len(checks),
        "failed": failed,
        "governed_source_images_available": 10,
        "governed_s03_source_sha256": GOVERNED_S03_SOURCE_SHA256,
        "email_fixture_sha256": fixture_sha,
        "email_fixture_dimensions": list(FIXTURE_DIMENSIONS),
        "tesseract_profile_outputs": observed,
        "s03_email_route": s03_route.get("decision"),
        "s03_email_resolved_text": s03_route.get("text"),
        "persistent_paddle_required_cases": 0,
        "persistent_paddle_required_case_names": [],
        "root_cause": "TESSERACT_LANGUAGE_PROFILE_SENSITIVITY",
        "historical_v2_preserved": True,
        "paddle_executed_for_s03": False,
        "paddle_runtime_promoted": False,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V3:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
