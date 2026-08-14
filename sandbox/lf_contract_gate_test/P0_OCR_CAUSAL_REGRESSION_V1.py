#!/usr/bin/env python3
"""Causal regression for EKB-P0-014 using the real reader function.

The fixture reproduces the geometry observed on canonical source e308b...:
`tu` is visually left of `deuda`, but its top y is four pixels lower.  The
regression invokes p0_full_reader_v4.ocr_lines itself and therefore fails if
that function sorts by y before x and only compares consecutive items.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "story_creator_p0_visual" / "v1.1" / "scripts"
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


def main() -> int:
    real_geometry = [
        {"text": "tu", "block_num": 6, "left": 67, "top": 324, "width": 38, "height": 28},
        {"text": "deuda", "block_num": 7, "left": 119, "top": 320, "width": 122, "height": 33},
    ]
    observed = _run(real_geometry)
    observed_texts = [item["text"] for item in observed]
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
    negative = _run(far_gap)
    negative_texts = [item["text"] for item in negative]
    if len(negative_texts) != 2 or set(negative_texts) != {"tu", "deuda"}:
        raise SystemExit(
            "FAIL_EKB_P0_014_OVERMERGE_GUARD: "
            f"expected two separate units observed={negative_texts!r}"
        )

    print(json.dumps({
        "result": "PASS",
        "ekb_code": "EKB-P0-014",
        "source_sha256": SOURCE_SHA,
        "real_geometry_recomposed": True,
        "token_order_left_to_right": True,
        "far_gap_remains_separate": True,
        "producer": "p0_full_reader_v4.ocr_lines",
        "production_authorized": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
