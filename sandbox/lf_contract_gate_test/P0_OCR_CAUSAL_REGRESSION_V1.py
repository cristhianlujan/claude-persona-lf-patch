#!/usr/bin/env python3
"""Causal regression for EKB-P0-014 using the real reader function.

The fixture reproduces the geometry observed on canonical source e308b...:
`tu` is visually left of `deuda`, but its top y is four pixels lower.  The
regression invokes p0_full_reader_v4.ocr_lines itself and therefore catches
ordering-dependent baseline reconstruction without copying the product logic.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1" / "scripts"
sys.path.insert(0, str(SCRIPTS))

import p0_full_reader_v4 as reader  # noqa: E402

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


def main() -> int:
    real_geometry = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 119, "top": 320, "width": 122, "height": 33},
    ]
    observed = _run(real_geometry)
    observed_texts = _texts(observed)
    if observed_texts != ["tu deuda"]:
        raise SystemExit(
            "FAIL_EKB_P0_014_REAL_GEOMETRY: "
            f"expected=['tu deuda'] observed={observed_texts!r} source={SOURCE_SHA}"
        )
    if observed[0].get("source_tokens") != ["tu", "deuda"]:
        raise SystemExit(
            "FAIL_EKB_P0_014_TOKEN_ORDER: "
            f"observed={observed[0].get('source_tokens')!r}"
        )

    far_gap = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 170, "top": 320, "width": 122, "height": 33},
    ]
    negative_gap = _texts(_run(far_gap))
    if len(negative_gap) != 2 or set(negative_gap) != {"tu", "deuda"}:
        raise SystemExit(
            "FAIL_EKB_P0_014_OVERMERGE_GAP: "
            f"expected two separate units observed={negative_gap!r}"
        )

    different_baseline = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 119, "top": 365, "width": 122, "height": 33},
    ]
    negative_baseline = _texts(_run(different_baseline))
    if len(negative_baseline) != 2 or set(negative_baseline) != {"tu", "deuda"}:
        raise SystemExit(
            "FAIL_EKB_P0_014_OVERMERGE_BASELINE: "
            f"expected two separate units observed={negative_baseline!r}"
        )

    compact_glyph = [
        {"text": "e", "block_num": 6, "left": 67, "top": 324, "width": 18, "height": 18},
        {"text": "correo", "block_num": 7, "left": 95, "top": 322, "width": 80, "height": 22},
    ]
    negative_glyph = _texts(_run(compact_glyph))
    if len(negative_glyph) != 2 or set(negative_glyph) != {"e", "correo"}:
        raise SystemExit(
            "FAIL_EKB_P0_014_GLYPH_GUARD: "
            f"expected compact glyph to remain separate observed={negative_glyph!r}"
        )

    reader_path = Path(reader.__file__).resolve()
    reader_file_sha256 = hashlib.sha256(reader_path.read_bytes()).hexdigest()
    print(json.dumps({
        "result": "PASS",
        "ekb_code": "EKB-P0-014",
        "source_sha256": SOURCE_SHA,
        "reader_file_sha256": reader_file_sha256,
        "real_geometry_recomposed": True,
        "token_order_left_to_right": True,
        "far_gap_remains_separate": True,
        "different_baseline_remains_separate": True,
        "compact_glyph_remains_separate": True,
        "producer": "p0_full_reader_v4.ocr_lines",
        "production_authorized": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
