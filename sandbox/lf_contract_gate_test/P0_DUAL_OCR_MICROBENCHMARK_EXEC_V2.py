#!/usr/bin/env python3
"""Corrected execution shim for the isolated dual-OCR microbenchmark.

All governed target slices are single-line. Reconstruct them left-to-right so
minor OCR baseline jitter cannot reorder words and bias either engine.
"""
from __future__ import annotations

import P0_DUAL_OCR_MICROBENCHMARK_EXEC_V1 as v1


def single_line_slice_text(obs: list[dict], roi: list[int]) -> tuple[str, float]:
    hits = [
        item for item in obs
        if v1.bbox_intersection_fraction(item["bbox"], roi) >= 0.10
        or v1.bbox_intersection_fraction(roi, item["bbox"]) >= 0.10
    ]
    hits.sort(key=lambda item: (item["bbox"][0], item["bbox"][1]))
    return (
        " ".join(item["text"] for item in hits).strip(),
        (sum(item["confidence"] for item in hits) / len(hits) if hits else 0.0),
    )


v1._slice_text = single_line_slice_text

if __name__ == "__main__":
    raise SystemExit(v1.main())
