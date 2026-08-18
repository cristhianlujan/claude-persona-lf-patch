#!/usr/bin/env python3
"""Root-cause regression wrapper for OCR cases 23/29/30 plus legacy EKB gates."""
from __future__ import annotations

import inspect
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPTS))

import p0_full_reader_v4 as reader  # noqa: E402
import P0_OCR_CAUSAL_REGRESSION_V1_CORE as legacy  # noqa: E402


def _token(text: str, x: int, width: int, *, y: int = 565, height: int = 18) -> dict:
    return {"text": text, "x": x, "y": y, "width": width, "height": height}


def _text_groups(groups: list[list[dict]]) -> list[list[str]]:
    return [[str(item.get("text") or "") for item in group] for group in groups]


def run_root_regressions() -> None:
    segmented = reader.segment_ocr_line_items([
        _token("Y", 626, 14),
        _token("+51", 675, 30),
        _token("Ej.", 749, 20),
        _token("987", 775, 28),
        _token("654", 809, 28),
        _token("321", 843, 28),
    ])
    observed = _text_groups(segmented)
    expected = [["Y"], ["+51"], ["Ej.", "987", "654", "321"]]
    if observed != expected:
        raise SystemExit(f"FAIL_OCR_ROOT_GEOMETRIC_OWNERSHIP:{observed!r}")

    normal = reader.segment_ocr_line_items([
        _token("Carta", 100, 63, y=100, height=19),
        _token("de", 172, 28, y=100, height=18),
        _token("No", 211, 32, y=101, height=18),
        _token("Adeudo", 251, 93, y=100, height=19),
    ])
    if _text_groups(normal) != [["Carta", "de", "No", "Adeudo"]]:
        raise SystemExit(f"FAIL_OCR_ROOT_GEOMETRIC_OVERSEGMENT:{_text_groups(normal)!r}")

    short_word = reader.segment_ocr_line_items([
        _token("de", 100, 18, y=100, height=18),
        _token("pago", 132, 42, y=100, height=18),
    ])
    if _text_groups(short_word) != [["de", "pago"]]:
        raise SystemExit(f"FAIL_OCR_ROOT_SHORT_WORD_OVERSEGMENT:{_text_groups(short_word)!r}")

    consensus = reader.resolve_ocr_consensus(["55 12345678", "Ej. 12345678", "Ej. 12345678"])
    if consensus.get("text") != "Ej. 12345678" or consensus.get("support") != 2 or consensus.get("method") != "INDEPENDENT_PSM_EXACT":
        raise SystemExit(f"FAIL_OCR_ROOT_CONSENSUS:{consensus!r}")

    no_majority = reader.resolve_ocr_consensus(["ABC 123", "ABD 123", "ABE 123"])
    if no_majority.get("method") != "NO_MAJORITY" or no_majority.get("support") != 1:
        raise SystemExit(f"FAIL_OCR_ROOT_FALSE_CONSENSUS:{no_majority!r}")

    low_confidence = {
        "elements": [{
            "element_id": "T-LOW", "element_type": "TEXT", "visible_text": "55 12345678",
            "classification": "INFERRED", "confidence": 0.50,
            "region": {"x": 10, "y": 10, "width": 150, "height": 20},
            "ocr_variants": ["55 12345678", "Ej. 12345678", "Ej. 12345678"],
            "independent_redetection": False, "redetection_status": "AMBIGUOUS",
        }],
        "reader_uncertainties": [{"element_id": "T-LOW", "code": "OCR_DISAGREEMENT"}],
        "raw_observations": {},
    }
    resolved_low = reader.resolve_reader_output(low_confidence, None, strict=True)
    low = resolved_low["elements"][0]
    if low.get("visible_text") != "Ej. 12345678" or low.get("classification") != "INFERRED":
        raise SystemExit(f"FAIL_OCR_ROOT_CONFIDENCE_INFLATION:{low!r}")

    replacement = reader.single_internal_symbol_replacement("Ej. miguelxcorreo.com", "Ej. miguel@correo.com")
    if replacement != {"from": "x", "to": "@"}:
        raise SystemExit(f"FAIL_OCR_ROOT_SYMBOL_PROOF:{replacement!r}")
    if reader.single_internal_symbol_replacement("abcxdef.com", "abc@dxf.com") is not None:
        raise SystemExit("FAIL_OCR_ROOT_MULTI_EDIT_ACCEPTED")
    if reader.single_internal_symbol_replacement("abcdef.com", "abc@def.com") is not None:
        raise SystemExit("FAIL_OCR_ROOT_SYMBOL_INSERTION_ACCEPTED")

    same_profile = reader._targeted_consensus([
        {"variant_id": "spa-7", "language_profile": "spa", "text": "a@b.com"},
        {"variant_id": "spa-11", "language_profile": "spa", "text": "a@b.com"},
    ])
    if same_profile is not None:
        raise SystemExit(f"FAIL_OCR_ROOT_SAME_PROFILE_FALSE_INDEPENDENCE:{same_profile!r}")

    profiles = reader._available_target_profiles()
    if not {"eng", "spa+eng"}.issubset(set(profiles)):
        raise SystemExit(f"FAIL_OCR_ROOT_PROFILE_DIVERSITY_UNAVAILABLE:{profiles!r}")

    original_attempts = reader._targeted_profile_attempts
    try:
        reader._targeted_profile_attempts = lambda image, region: [
            {"variant_id": "eng-11", "language_profile": "eng", "text": "Ej. miguel@correo.com"},
            {"variant_id": "spa-eng-11", "language_profile": "spa+eng", "text": "Ej. miguel@correo.com"},
        ]
        symbol_candidate = {
            "elements": [{
                "element_id": "T-SYMBOL", "element_type": "TEXT", "visible_text": "Ej. miguelxcorreo.com",
                "classification": "INFERRED", "confidence": 0.90,
                "region": {"x": 10, "y": 10, "width": 220, "height": 22},
                "ocr_variants": ["Ej. miguelecorreo.com", "Ej. miguelxcorreo.com", "Ej. miguelxcorreo.com"],
                "independent_redetection": False, "redetection_status": "AMBIGUOUS",
            }],
            "reader_uncertainties": [{"element_id": "T-SYMBOL", "code": "OCR_DISAGREEMENT"}],
            "raw_observations": {},
        }
        original_purity = reader.annotate_evidence_purity
        reader.annotate_evidence_purity = lambda elements: None
        try:
            symbol_out = reader.resolve_reader_output(symbol_candidate, object(), strict=True)
        finally:
            reader.annotate_evidence_purity = original_purity
    finally:
        reader._targeted_profile_attempts = original_attempts

    symbol = symbol_out["elements"][0]
    if symbol.get("visible_text") != "Ej. miguel@correo.com" or symbol.get("redetection_status") != "CROSS_PROFILE_REDETECTED" or symbol.get("targeted_symbol_replacement") != {"from": "x", "to": "@"}:
        raise SystemExit(f"FAIL_OCR_ROOT_LOCALIZED_REDETECTION:{symbol!r}")
    if set(symbol.get("targeted_ocr_language_profiles") or []) != {"eng", "spa+eng"}:
        raise SystemExit(f"FAIL_OCR_ROOT_PROFILE_TRACE:{symbol!r}")
    if any(item.get("element_id") == "T-SYMBOL" and item.get("code") == "OCR_DISAGREEMENT" for item in symbol_out.get("reader_uncertainties") or []):
        raise SystemExit("FAIL_OCR_ROOT_RESOLVED_DEBT_PERSISTED")

    production_source = inspect.getsource(reader)
    forbidden = ("55 12345678", "987 654 321", "miguel@correo", "case 23", "case 29", "case 30")
    present = [literal for literal in forbidden if literal.casefold() in production_source.casefold()]
    if present:
        raise SystemExit(f"FAIL_OCR_ROOT_SCREEN_LITERAL:{present!r}")

    print("PASS_P0_OCR_ROOT_REMEDIATION=11/11")


def main() -> int:
    run_root_regressions()
    return legacy.main()


if __name__ == "__main__":
    raise SystemExit(main())
