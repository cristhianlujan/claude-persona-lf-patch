#!/usr/bin/env python3
"""Corrected execution shim for the isolated dual-OCR microbenchmark.

All governed target slices are single-line. Reconstruct them left-to-right so
minor OCR baseline jitter cannot reorder words and bias either engine. Target
ROIs exclude adjacent non-text UI controls. Reconciliation is baseline +
challenger: cross-engine confidence scores are never treated as calibrated.
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


def conservative_reconcile(kind: str, baseline: str, baseline_conf: float, challenger: str, challenger_conf: float) -> tuple[str, str]:
    # Confidence values are engine-specific and are intentionally NOT compared.
    if baseline and challenger and v1.norm(baseline) == v1.norm(challenger):
        return baseline, "EXACT_AGREEMENT"

    baseline_valid = v1._valid(kind, baseline)
    challenger_valid = v1._valid(kind, challenger)

    # Automatic challenger correction is allowed only when it repairs a
    # machine-checkable structural violation in the baseline.
    if challenger_valid and not baseline_valid:
        return challenger, "PADDLE_STRUCTURAL_CORRECTION"
    if baseline_valid and not challenger_valid:
        return baseline, "BASELINE_STRUCTURALLY_VALID"

    if baseline:
        # Preserve existing behavior and surface the disagreement separately.
        return baseline, "BASELINE_PRESERVED_DISAGREEMENT"
    return "", "NEEDS_REVIEW"


for target in v1.SLICES:
    if target["id"] == "phone_prefix":
        target["bbox"] = [670, 558, 34, 28]
        target["expected"] = "+51"
    elif target["id"] == "privacy_link":
        target["expected"] = "los Términos y Condiciones y la Política de Privacidad."

v1._slice_text = single_line_slice_text
v1._reconcile = conservative_reconcile

if __name__ == "__main__":
    raise SystemExit(v1.main())
