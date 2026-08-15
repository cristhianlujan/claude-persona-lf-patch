#!/usr/bin/env python3
"""Source-bound regression for fail-closed masked structured values.

The real non-holdout source shows a partially obscured email. Tesseract can
stably render the hidden bullets as repeated asterisks, which V3's broad email
syntax accepted. V6 proves that obscuration evidence now blocks exact truth and
Paddle reconstruction while preserving ordinary structured values.

LOTE-REM-PR166-02 adds adversarial checks for ARC-014: duplicate stable
variant_id values may coalesce only when their relevant payload is equivalent;
conflicting duplicates must fail closed independent of input order.
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

    # F-PR166-01: exercise the Paddle lane from an unmasked observation that
    # legitimately reaches PADDLE_REQUIRED.
    unmasked_paddle_case = {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": "tucorreoOemail.com",
        "targeted_attempts": [
            t_attempt("v1", "tucorreoOemail.com", "eng"),
            t_attempt("v2", "tucorreo0email.com", "spa"),
        ],
        "challenger_allowed": True,
    }

    checks["unmasked_case_reaches_paddle_lane"] = (
        router.route_observation(unmasked_paddle_case).get("decision") == "PADDLE_REQUIRED"
    )

    _star = router.reconcile_paddle(
        unmasked_paddle_case,
        [p_attempt("p1", "jus***@gmail.com"), p_attempt("p2", "jus***@gmail.com")],
    )
    checks["paddle_star_masked_output_rejected"] = (
        _star.get("decision") == "PADDLE_MASKED_NO_COMPLETION"
        and _star.get("resolved") is False
        and _star.get("text") is None
    )

    _bullet = router.reconcile_paddle(
        unmasked_paddle_case,
        [p_attempt("p1", "ju•••@gmail.com"), p_attempt("p2", "ju•••@gmail.com")],
    )
    checks["paddle_bullet_masked_output_rejected"] = (
        _bullet.get("decision") == "PADDLE_MASKED_NO_COMPLETION"
        and _bullet.get("resolved") is False
    )

    _mixed = router.reconcile_paddle(
        unmasked_paddle_case,
        [
            p_attempt("p1", "jus***@gmail.com"),
            p_attempt("p2", "tucorreo@email.com"),
            p_attempt("p3", "tucorreo@email.com"),
        ],
    )
    checks["paddle_mixed_masked_batch_rejected"] = (
        _mixed.get("decision") == "PADDLE_MASKED_NO_COMPLETION"
        and _mixed.get("resolved") is False
    )

    _card_case = {
        "materiality": "TEXT",
        "kind": "card_number",
        "baseline_text": "4111 1111 1111 111X",
        "targeted_attempts": [
            t_attempt("v1", "4111 1111 1111 111X", "eng"),
            t_attempt("v2", "4111-1111-1111-111O", "spa"),
        ],
        "challenger_allowed": True,
    }
    _card = router.reconcile_paddle(
        _card_case,
        [p_attempt("p1", "•••• •••• •••• 1111"), p_attempt("p2", "•••• •••• •••• 1111")],
    )
    checks["paddle_masked_card_rejected"] = (
        _card.get("decision") == "PADDLE_MASKED_NO_COMPLETION"
    )

    _ok = router.reconcile_paddle(
        unmasked_paddle_case,
        [p_attempt("p1", "tucorreo@email.com"), p_attempt("p2", "tucorreo@email.com")],
    )
    checks["paddle_unmasked_repair_preserved"] = (
        _ok.get("decision") == "PADDLE_STRUCTURAL_CORRECTION"
        and _ok.get("resolved") is True
        and _ok.get("text") == "tucorreo@email.com"
    )

    _no_consensus = router.reconcile_paddle(
        unmasked_paddle_case,
        [p_attempt("p1", "tucorreo@email.com"), p_attempt("p2", "otro@email.com")],
    )
    checks["paddle_without_consensus_still_needs_review"] = (
        _no_consensus.get("decision") == "NEEDS_REVIEW"
        and _no_consensus.get("resolved") is False
    )

    checks["mask_guard_precedes_non_text_gate"] = router.route_observation({
        "materiality": "NON_TEXT_QR", "kind": "email",
        "baseline_text": "jus***@gmail.com",
        "targeted_attempts": [], "challenger_allowed": False,
    }).get("decision") == "VISIBLE_MASKED_NO_COMPLETION"

    checks["mask_guard_precedes_structural_gate"] = router.route_observation({
        "materiality": "TEXT", "kind": "card_number",
        "baseline_text": "•••• 1234",
        "structural_resolution_proven": True,
        "structural_resolution_code": "PIXEL_FILLED_DOT_MASK_NORMALIZATION",
        "targeted_attempts": [], "challenger_allowed": False,
    }).get("decision") == "VISIBLE_MASKED_NO_COMPLETION"

    checks["single_bullet_blocks"] = router.is_masked_structured_text("ju•@gmail.com") is True
    checks["double_star_does_not_block"] = router.is_masked_structured_text("ab**c@example.com") is False

    # ARC-014 RED/GREEN matrix. Stable variant IDs are identity claims; two
    # materially different payloads with the same ID are contradictory evidence.
    _dup_same = {
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("dup", "tucorreo@email.com", "eng"),
            t_attempt("dup", "tucorreo@email.com", "eng"),
        ],
        "challenger_allowed": True,
    }
    _dup_same_route = router.route_observation(_dup_same)
    checks["duplicate_id_same_payload_benign"] = _dup_same_route.get("decision") != "EVIDENCE_VARIANT_ID_CONFLICT"
    checks["duplicate_id_same_payload_counts_once"] = _dup_same_route.get("targeted_attempt_count") == 1

    def _dup_conflict_route(first: str, second: str, first_profile: str = "eng", second_profile: str = "eng") -> dict:
        return router.route_observation({
            "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
            "targeted_attempts": [
                t_attempt("dup", first, first_profile),
                t_attempt("dup", second, second_profile),
                t_attempt("other", first, "spa"),
            ],
            "challenger_allowed": True,
        })

    _clean_masked = _dup_conflict_route("tucorreo@email.com", "jus***@gmail.com")
    _masked_clean = _dup_conflict_route("jus***@gmail.com", "tucorreo@email.com")
    checks["duplicate_id_clean_then_masked_conflict"] = (
        _clean_masked.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and _clean_masked.get("resolved") is False
        and _clean_masked.get("invoke_paddle") is False
    )
    checks["duplicate_id_masked_then_clean_conflict"] = (
        _masked_clean.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and _masked_clean.get("resolved") is False
        and _masked_clean.get("invoke_paddle") is False
    )
    checks["duplicate_id_conflict_order_invariant"] = _clean_masked.get("decision") == _masked_clean.get("decision")

    _valid_valid = _dup_conflict_route("alpha@example.com", "beta@example.com")
    checks["duplicate_id_valid_text_conflict"] = _valid_valid.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"

    _profile_mismatch = _dup_conflict_route(
        "tucorreo@email.com", "tucorreo@email.com", first_profile="eng", second_profile="spa"
    )
    checks["duplicate_id_profile_mismatch_conflict"] = _profile_mismatch.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"

    _t_conflict = _dup_conflict_route("tucorreo@email.com", "otro@email.com")
    checks["tesseract_duplicate_conflict_not_consensus"] = (
        _t_conflict.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and _t_conflict.get("decision") != "TARGETED_TESSERACT_ACCEPT"
    )

    _unique_consensus = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("u1", "tucorreo@email.com", "eng"),
            t_attempt("u2", "tucorreo@email.com", "spa"),
        ],
        "challenger_allowed": True,
    })
    checks["unique_ids_legitimate_consensus_preserved"] = (
        _unique_consensus.get("decision") == "TARGETED_TESSERACT_ACCEPT"
        and _unique_consensus.get("resolved") is True
    )

    _empty_ids = router.route_observation({
        "materiality": "TEXT", "kind": "email", "baseline_text": "bad-email",
        "targeted_attempts": [
            t_attempt("", "alpha@example.com", "eng"),
            t_attempt("", "beta@example.com", "spa"),
            t_attempt("u1", "alpha@example.com", "eng"),
        ],
        "challenger_allowed": True,
    })
    checks["empty_ids_do_not_create_conflict"] = _empty_ids.get("decision") != "EVIDENCE_VARIANT_ID_CONFLICT"

    def _paddle_conflict(first: str, second: str) -> dict:
        return router.reconcile_paddle(
            unmasked_paddle_case,
            [
                p_attempt("p1", first),
                p_attempt("p1", second),
                p_attempt("p2", first),
            ],
        )

    _p_clean_masked = _paddle_conflict("tucorreo@email.com", "jus***@gmail.com")
    _p_masked_clean = _paddle_conflict("jus***@gmail.com", "tucorreo@email.com")
    checks["paddle_duplicate_id_clean_then_masked_conflict"] = (
        _p_clean_masked.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and _p_clean_masked.get("resolved") is False
    )
    checks["paddle_duplicate_id_masked_then_clean_conflict"] = (
        _p_masked_clean.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and _p_masked_clean.get("resolved") is False
    )
    checks["paddle_duplicate_id_conflict_order_invariant"] = (
        _p_clean_masked.get("decision") == _p_masked_clean.get("decision")
    )
    _p_valid_valid = _paddle_conflict("alpha@example.com", "beta@example.com")
    checks["paddle_duplicate_id_valid_text_conflict"] = _p_valid_valid.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"

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
        "remediated_findings": ["F-PR166-01", "F-PR166-02", "F-PR166-03", "ARC-014"],
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
