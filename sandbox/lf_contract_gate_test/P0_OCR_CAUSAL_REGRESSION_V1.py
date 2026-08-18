#!/usr/bin/env python3
"""Causal regression for OCR grouping, consensus, and glyph uncertainty.

Uses product reader functions directly. Regression fixtures may preserve real failure
shapes/text, while production logic must stay source-agnostic and coordinate-free.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPTS))

import p0_full_reader_v4 as reader  # noqa: E402
import p0_visual_real_rerun_support_v4 as rerun_support  # noqa: E402

SOURCE_SHA = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"


def _payload(items: list[dict]) -> dict:
    fields = (
        "text", "conf", "block_num", "par_num", "line_num", "left", "top",
        "width", "height", "page_num", "word_num",
    )
    out = {field: [] for field in fields}
    for item in items:
        out["text"].append(item["text"])
        out["conf"].append(str(item.get("conf", 96.0)))
        out["block_num"].append(item["block_num"])
        out["par_num"].append(item.get("par_num", 1))
        out["line_num"].append(item.get("line_num", 1))
        out["left"].append(item["left"])
        out["top"].append(item["top"])
        out["width"].append(item["width"])
        out["height"].append(item["height"])
        out["page_num"].append(1)
        out["word_num"].append(1)
    return out


def _run(items: list[dict]) -> list[dict]:
    original = reader.pytesseract.image_to_data
    try:
        data = _payload(items)
        reader.pytesseract.image_to_data = lambda *args, **kwargs: data
        return reader.ocr_lines(object(), 3)
    finally:
        reader.pytesseract.image_to_data = original


def _texts(items: list[dict]) -> list[str]:
    return [item["text"] for item in items]


class _FakeImage:
    shape = (100, 100, 3)


def _reader_line(text: str, *, width: int, height: int, psm: int, confidence: float = 50.0) -> dict:
    region = {"x": 10, "y": 10, "width": width, "height": height}
    return {
        "text": text,
        "confidence": confidence,
        "region": region,
        "block_id": 1,
        "paragraph_id": 1,
        "line_id": 1,
        "segment_index": 1,
        "origin_psm": psm,
        "token_count": 1,
        "source_tokens": [text],
        "source_token_ids": [f"TEST-{psm}-1"],
        "source_token_regions": [dict(region)],
        "source_line_keys": [f"{psm}:1:1:1"],
        "partition_boundary_before": None,
    }


def _run_full_reader_uncertainty_case(text: str, *, width: int, height: int) -> dict:
    originals = {
        "imread": reader.cv2.imread,
        "ocr_lines": reader.ocr_lines,
        "detect_compact_visuals": reader.detect_compact_visuals,
        "grouping_signal": reader.grouping_signal,
        "cv_objects": reader.cv_objects,
        "crop_evidence_ref": reader.crop_evidence_ref,
        "crop_sha256": reader.crop_sha256,
        "annotate_evidence_purity": reader.annotate_evidence_purity,
    }
    try:
        reader.cv2.imread = lambda *args, **kwargs: _FakeImage()
        reader.ocr_lines = lambda image, psm: [_reader_line(text, width=width, height=height, psm=psm)]
        reader.detect_compact_visuals = lambda image, observations: []
        reader.grouping_signal = lambda primary, lines, primary_psm, source_sha: (
            False,
            "TG-TEST",
            ["p0://test/source-observation"],
            {"3": 1, "11": 2, "12": 2},
        )
        reader.cv_objects = lambda image, text_regions: []
        reader.crop_evidence_ref = lambda *args, **kwargs: "p0://test/crop"
        reader.crop_sha256 = lambda *args, **kwargs: "0" * 64
        reader.annotate_evidence_purity = lambda elements: None
        return reader.full_reader(
            "fixture.png",
            {
                "source_sha256": SOURCE_SHA,
                "reader_execution_id": "EXEC-P0-OCR-CLASSIFICATION-REGRESSION",
                "pass_id": "PASS-P0-OCR-CLASSIFICATION-REGRESSION",
                "remediation_state": {"strict_mode": True},
            },
        )
    finally:
        reader.cv2.imread = originals["imread"]
        reader.ocr_lines = originals["ocr_lines"]
        reader.detect_compact_visuals = originals["detect_compact_visuals"]
        reader.grouping_signal = originals["grouping_signal"]
        reader.cv_objects = originals["cv_objects"]
        reader.crop_evidence_ref = originals["crop_evidence_ref"]
        reader.crop_sha256 = originals["crop_sha256"]
        reader.annotate_evidence_purity = originals["annotate_evidence_purity"]


def _run_full_reader_variants(text_by_psm: dict[int, str], *, local_reads: dict[int, str] | None = None) -> dict:
    originals = {
        "imread": reader.cv2.imread,
        "ocr_lines": reader.ocr_lines,
        "image_to_string": reader.pytesseract.image_to_string,
        "detect_compact_visuals": reader.detect_compact_visuals,
        "grouping_signal": reader.grouping_signal,
        "cv_objects": reader.cv_objects,
        "crop_evidence_ref": reader.crop_evidence_ref,
        "crop_sha256": reader.crop_sha256,
        "annotate_evidence_purity": reader.annotate_evidence_purity,
    }
    image = np.zeros((100, 240, 3), dtype=np.uint8)
    try:
        reader.cv2.imread = lambda *args, **kwargs: image
        reader.ocr_lines = lambda image, psm: [
            _reader_line(text_by_psm[psm], width=180, height=18, psm=psm, confidence=70.0)
        ]
        if local_reads is not None:
            def _localized(*args, **kwargs):
                config = str(kwargs.get("config") or "")
                psm = next((value for value in (6, 7, 11) if f"--psm {value}" in config), 7)
                return local_reads[psm]
            reader.pytesseract.image_to_string = _localized
        reader.detect_compact_visuals = lambda image, observations: []
        reader.grouping_signal = lambda primary, lines, primary_psm, source_sha: (
            True,
            "TG-ROOTFIX",
            ["p0://test/source-observation"],
            {"3": 1, "11": 1, "12": 1},
        )
        reader.cv_objects = lambda image, text_regions: []
        reader.crop_evidence_ref = lambda *args, **kwargs: "p0://test/crop"
        reader.crop_sha256 = lambda *args, **kwargs: "0" * 64
        reader.annotate_evidence_purity = lambda elements: None
        return reader.full_reader(
            "fixture.png",
            {
                "source_sha256": SOURCE_SHA,
                "reader_execution_id": "EXEC-P0-OCR-ROOTFIX-REGRESSION",
                "pass_id": "PASS-P0-OCR-ROOTFIX-REGRESSION",
                "remediation_state": {"strict_mode": True},
            },
        )
    finally:
        reader.cv2.imread = originals["imread"]
        reader.ocr_lines = originals["ocr_lines"]
        reader.pytesseract.image_to_string = originals["image_to_string"]
        reader.detect_compact_visuals = originals["detect_compact_visuals"]
        reader.grouping_signal = originals["grouping_signal"]
        reader.cv_objects = originals["cv_objects"]
        reader.crop_evidence_ref = originals["crop_evidence_ref"]
        reader.crop_sha256 = originals["crop_sha256"]
        reader.annotate_evidence_purity = originals["annotate_evidence_purity"]


def _postremediation_fixture() -> tuple[dict, dict]:
    region = {"x": 467, "y": 723, "width": 23, "height": 28}
    candidate = {
        "elements": [{
            "element_id": "V4-T-POST",
            "classification": "INFERRED",
            "element_type": "TEXT",
            "visible_text": "10",
            "region": dict(region),
            "semantic_role": "visible_copy",
            "ocr_consensus_text": "10",
            "independent_redetection": False,
            "redetection_status": "AMBIGUOUS",
            "graphic_score": 0.05,
        }],
        "reader_uncertainties": [
            {"element_id": "V4-T-POST", "code": "OCR_DISAGREEMENT", "region": dict(region)},
            {"element_id": "V4-T-POST", "code": "TEXT_GROUPING_DISAGREEMENT", "region": dict(region)},
            {"element_id": "OTHER", "code": "OCR_DISAGREEMENT", "region": {"x": 1, "y": 1, "width": 10, "height": 10}},
        ],
    }
    state = {
        "unsupported_short_text_regions": [{
            "region": dict(region),
            "source_category": "SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT",
        }]
    }
    return candidate, state


def main() -> int:
    real_geometry = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 119, "top": 320, "width": 122, "height": 33},
    ]
    observed = _run(real_geometry)
    observed_texts = _texts(observed)
    if observed_texts != ["tu deuda"]:
        raise SystemExit(f"FAIL_EKB_P0_014_REAL_GEOMETRY:{observed_texts!r}")
    if observed[0].get("source_tokens") != ["tu", "deuda"]:
        raise SystemExit(f"FAIL_EKB_P0_014_TOKEN_ORDER:{observed[0].get('source_tokens')!r}")

    far_gap = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 170, "top": 320, "width": 122, "height": 33},
    ]
    negative_gap = _texts(_run(far_gap))
    if len(negative_gap) != 2 or set(negative_gap) != {"tu", "deuda"}:
        raise SystemExit(f"FAIL_EKB_P0_014_OVERMERGE_GAP:{negative_gap!r}")

    different_baseline = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 119, "top": 365, "width": 122, "height": 33},
    ]
    negative_baseline = _texts(_run(different_baseline))
    if len(negative_baseline) != 2 or set(negative_baseline) != {"tu", "deuda"}:
        raise SystemExit(f"FAIL_EKB_P0_014_OVERMERGE_BASELINE:{negative_baseline!r}")

    compact_glyph = [
        {"text": "e", "block_num": 6, "left": 67, "top": 324, "width": 18, "height": 18},
        {"text": "correo", "block_num": 7, "left": 95, "top": 322, "width": 80, "height": 22},
    ]
    negative_glyph = _texts(_run(compact_glyph))
    if len(negative_glyph) != 2 or set(negative_glyph) != {"e", "correo"}:
        raise SystemExit(f"FAIL_EKB_P0_014_GLYPH_GUARD:{negative_glyph!r}")

    # Root cause regression: a single OCR line containing three visually independent
    # tokens must be repartitioned by relative geometry, while normal prose remains intact.
    contaminated = {
        "text": "OD +5s1v 8j.987654321",
        "confidence": 56.0,
        "region": {"x": 626, "y": 565, "width": 221, "height": 21},
        "block_id": 29,
        "paragraph_id": 2,
        "line_id": 2,
        "segment_index": 1,
        "origin_psm": 3,
        "token_count": 3,
        "source_tokens": ["OD", "+5s1v", "8j.987654321"],
        "source_token_ids": ["T1", "T2", "T3"],
        "source_token_regions": [
            {"x": 626, "y": 565, "width": 14, "height": 21},
            {"x": 675, "y": 570, "width": 43, "height": 11},
            {"x": 749, "y": 570, "width": 98, "height": 13},
        ],
        "source_line_keys": ["3:29:2:2"],
        "partition_boundary_before": None,
    }
    repartitioned = reader._refine_line_relative_geometry(contaminated)
    if [item["source_tokens"] for item in repartitioned] != [["OD"], ["+5s1v"], ["8j.987654321"]]:
        raise SystemExit(f"FAIL_ROOTFIX_RELATIVE_GAP_PARTITION:{repartitioned!r}")
    if repartitioned[-1]["region"] != {"x": 749, "y": 570, "width": 98, "height": 13}:
        raise SystemExit(f"FAIL_ROOTFIX_CROP_REGION:{repartitioned[-1]['region']!r}")

    normal_line = {
        "text": "tu deuda",
        "confidence": 90.0,
        "region": {"x": 67, "y": 320, "width": 174, "height": 33},
        "source_tokens": ["tu", "deuda"],
        "source_token_ids": ["N1", "N2"],
        "source_token_regions": [
            {"x": 67, "y": 324, "width": 38, "height": 28},
            {"x": 119, "y": 320, "width": 122, "height": 33},
        ],
        "source_line_keys": ["3:6:1:1"],
        "segment_index": 1,
        "partition_boundary_before": None,
    }
    if len(reader._refine_line_relative_geometry(normal_line)) != 1:
        raise SystemExit("FAIL_ROOTFIX_NORMAL_TEXT_OVERPARTITION")

    majority_text, majority_support = reader._consensus_from_variants(
        ["55 12345678", "Ej. 12345678", "Ej. 12345678"]
    )
    if majority_text != "Ej. 12345678" or majority_support != 2:
        raise SystemExit(f"FAIL_ROOTFIX_MAJORITY_CONSENSUS:{majority_text!r}:{majority_support}")

    case23 = _run_full_reader_variants({3: "55 12345678", 11: "Ej. 12345678", 12: "Ej. 12345678"})
    case23_text = [e for e in case23["elements"] if e.get("element_id", "").startswith("V4-T-")][0]
    if case23_text.get("visible_text") != "Ej. 12345678" or case23_text.get("ocr_consensus_text") != "Ej. 12345678":
        raise SystemExit(f"FAIL_ROOTFIX_CASE23_VISIBLE_CONSENSUS:{case23_text!r}")

    if not reader._symbol_only_delta("Ej. miguelxcorreo.com", "Ej. miguel@correo.com"):
        raise SystemExit("FAIL_ROOTFIX_SYMBOL_ONLY_ACCEPT")
    if reader._symbol_only_delta("Ej. miguelxcorreo.com", "Ej. maria@correo.com"):
        raise SystemExit("FAIL_ROOTFIX_SYMBOL_ONLY_WORD_REWRITE")

    case30 = _run_full_reader_variants(
        {3: "Ej. miguelecorreo.com", 11: "Ej. miguelxcorreo.com", 12: "Ej. miguelxcorreo.com"},
        local_reads={6: "Ej. miguel@correo.com", 7: "Ej. miguel@correo.com", 11: "Ej. miguel@correo.com"},
    )
    case30_text = [e for e in case30["elements"] if e.get("element_id", "").startswith("V4-T-")][0]
    if case30_text.get("visible_text") != "Ej. miguel@correo.com":
        raise SystemExit(f"FAIL_ROOTFIX_CASE30_AT_VISIBLE:{case30_text!r}")
    if case30_text.get("ocr_consensus_source") != "LOCALIZED_SYMBOL_REDETECTION":
        raise SystemExit(f"FAIL_ROOTFIX_CASE30_PROVENANCE:{case30_text!r}")
    if (case30_text.get("localized_redetection") or {}).get("support") != 3:
        raise SystemExit(f"FAIL_ROOTFIX_CASE30_SUPPORT:{case30_text!r}")

    glyph_output = _run_full_reader_uncertainty_case("e", width=18, height=18)
    glyph_elements = [item for item in glyph_output["elements"] if item.get("element_id", "").startswith("V4-T-")]
    if len(glyph_elements) != 1 or glyph_elements[0].get("element_type") != "ICON_OR_GLYPH":
        raise SystemExit(f"FAIL_EKB_P0_020_GLYPH_CLASSIFICATION:{glyph_elements!r}")
    glyph_codes = [item.get("code") for item in glyph_output["reader_uncertainties"]]
    if "OCR_DISAGREEMENT" in glyph_codes or "TEXT_GROUPING_DISAGREEMENT" in glyph_codes:
        raise SystemExit(f"FAIL_EKB_P0_020_GLYPH_FALSE_TEXT_UNCERTAINTY:{glyph_codes!r}")

    text_output = _run_full_reader_uncertainty_case("Correo", width=80, height=18)
    text_elements = [item for item in text_output["elements"] if item.get("element_id", "").startswith("V4-T-")]
    if len(text_elements) != 1 or text_elements[0].get("element_type") != "TEXT":
        raise SystemExit(f"FAIL_EKB_P0_020_TEXT_CLASSIFICATION:{text_elements!r}")
    text_codes = [item.get("code") for item in text_output["reader_uncertainties"]]
    if text_codes.count("OCR_DISAGREEMENT") != 1 or text_codes.count("TEXT_GROUPING_DISAGREEMENT") != 1:
        raise SystemExit(f"FAIL_EKB_P0_020_TEXT_UNCERTAINTY_LOST:{text_codes!r}")

    candidate, state = _postremediation_fixture()
    remediated = rerun_support._apply_remediation_state(candidate, state)
    remediated_element = remediated["elements"][0]
    if remediated_element.get("element_type") != "ICON_OR_GLYPH" or remediated_element.get("visible_text") is not None:
        raise SystemExit(f"FAIL_EKB_P0_020_POST_REMEDIATION_CLASSIFICATION:{remediated_element!r}")
    remaining = [(u.get("element_id"), u.get("code")) for u in remediated.get("reader_uncertainties") or []]
    if ("V4-T-POST", "OCR_DISAGREEMENT") in remaining or ("V4-T-POST", "TEXT_GROUPING_DISAGREEMENT") in remaining:
        raise SystemExit(f"FAIL_EKB_P0_020_POST_REMEDIATION_STALE_TEXT_DEBT:{remaining!r}")
    if ("OTHER", "OCR_DISAGREEMENT") not in remaining:
        raise SystemExit(f"FAIL_EKB_P0_020_POST_REMEDIATION_UNRELATED_DEBT_LOST:{remaining!r}")
    remediation_codes = [u.get("code") for u in remediated.get("uncertainties") or []]
    if remediation_codes.count("UNSUPPORTED_SHORT_TEXT_RECLASSIFIED") != 1:
        raise SystemExit(f"FAIL_EKB_P0_020_POST_REMEDIATION_TRACE_LOST:{remediation_codes!r}")

    reader_path = Path(reader.__file__).resolve()
    support_path = Path(rerun_support.__file__).resolve()
    print(json.dumps({
        "result": "PASS",
        "ekb_code": "EKB-P0-014",
        "ekb_codes": ["EKB-P0-014", "EKB-P0-020"],
        "classification_ekb_code": "EKB-P0-020",
        "source_sha256": SOURCE_SHA,
        "reader_file_sha256": hashlib.sha256(reader_path.read_bytes()).hexdigest(),
        "rerun_support_file_sha256": hashlib.sha256(support_path.read_bytes()).hexdigest(),
        "real_geometry_recomposed": True,
        "token_order_left_to_right": True,
        "far_gap_remains_separate": True,
        "different_baseline_remains_separate": True,
        "compact_glyph_remains_separate": True,
        "relative_gap_repartition": True,
        "crop_contamination_removed": True,
        "majority_consensus_selected": True,
        "localized_symbol_redetection": True,
        "symbol_only_rewrite_guard": True,
        "glyph_false_text_uncertainty_suppressed": True,
        "genuine_text_uncertainty_preserved": True,
        "postremediation_stale_text_uncertainty_suppressed": True,
        "postremediation_trace_preserved": True,
        "unrelated_reader_uncertainty_preserved": True,
        "producer": "p0_full_reader_v4.ocr_lines+refine_ocr_geometry",
        "classification_producer": "p0_full_reader_v4+p0_visual_real_rerun_support_v4",
        "production_authorized": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
