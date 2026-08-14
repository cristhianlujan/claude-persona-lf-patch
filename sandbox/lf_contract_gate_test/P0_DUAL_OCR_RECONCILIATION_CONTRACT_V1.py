#!/usr/bin/env python3
"""Pure contract for a future independent OCR challenger.

This does not load PaddleOCR or promote a second engine. It freezes the safety
invariants learned by the exact-head microbenchmark so a later runtime change
cannot silently degrade into uncalibrated confidence voting.
"""
from __future__ import annotations

import re

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def norm(value: str) -> str:
    return " ".join((value or "").casefold().split())


def structurally_valid(kind: str, value: str) -> bool:
    text = (value or "").strip()
    compact = text.replace(" ", "")
    if not text:
        return False
    if kind == "email":
        candidate = text[3:].strip() if text.casefold().startswith("ej.") else text
        return bool(EMAIL_RE.fullmatch(candidate))
    if kind == "phone_prefix":
        return "+51" in compact
    if kind == "phone":
        return sum(ch.isdigit() for ch in text) >= 9
    if kind == "document_number":
        return sum(ch.isdigit() for ch in text) >= 8
    return True


def reconcile(
    *,
    kind: str,
    baseline: str,
    challenger: str,
    baseline_confidence: float | None = None,
    challenger_confidence: float | None = None,
) -> tuple[str, str]:
    """Conservative baseline + challenger reconciliation.

    Confidence arguments are accepted for evidence transport only. The decision
    logic deliberately never compares them across engines.
    """
    del baseline_confidence, challenger_confidence
    if baseline and challenger and norm(baseline) == norm(challenger):
        return baseline, "EXACT_AGREEMENT"

    baseline_valid = structurally_valid(kind, baseline)
    challenger_valid = structurally_valid(kind, challenger)

    if challenger_valid and not baseline_valid:
        return challenger, "CHALLENGER_STRUCTURAL_CORRECTION"
    if baseline_valid and not challenger_valid:
        return baseline, "BASELINE_STRUCTURALLY_VALID"
    if baseline:
        return baseline, "BASELINE_PRESERVED_DISAGREEMENT"
    return "", "NEEDS_REVIEW"


def check(condition: bool, name: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL_DUAL_OCR_RECONCILIATION:{name}")


def main() -> int:
    passed = 0

    out = reconcile(kind="email", baseline="Ej. miguel@correo.com", challenger="Ej. miguel@correo.com")
    check(out == ("Ej. miguel@correo.com", "EXACT_AGREEMENT"), "exact_agreement")
    passed += 1

    out = reconcile(kind="email", baseline="Ej. miguelxcorreo.com", challenger="Ej. miguel@correo.com")
    check(out == ("Ej. miguel@correo.com", "CHALLENGER_STRUCTURAL_CORRECTION"), "email_structural_correction")
    passed += 1

    out = reconcile(kind="email", baseline="Ej. miguel@correo.com", challenger="Ej. miguelxcorreo.com")
    check(out == ("Ej. miguel@correo.com", "BASELINE_STRUCTURALLY_VALID"), "preserve_valid_baseline")
    passed += 1

    out = reconcile(kind="text", baseline="Política de Privacidad.", challenger="Política de Privacidad")
    check(out == ("Política de Privacidad.", "BASELINE_PRESERVED_DISAGREEMENT"), "both_valid_disagreement")
    passed += 1

    low_high = reconcile(
        kind="text", baseline="baseline", challenger="challenger",
        baseline_confidence=0.01, challenger_confidence=0.99,
    )
    high_low = reconcile(
        kind="text", baseline="baseline", challenger="challenger",
        baseline_confidence=0.99, challenger_confidence=0.01,
    )
    check(low_high == high_low == ("baseline", "BASELINE_PRESERVED_DISAGREEMENT"), "confidence_not_cross_calibrated")
    passed += 1

    out = reconcile(kind="phone_prefix", baseline="+51", challenger="51")
    check(out == ("+51", "BASELINE_STRUCTURALLY_VALID"), "phone_prefix_guard")
    passed += 1

    out = reconcile(kind="document_number", baseline="Ej. 12345678", challenger="Ej. 1234567")
    check(out == ("Ej. 12345678", "BASELINE_STRUCTURALLY_VALID"), "document_guard")
    passed += 1

    out = reconcile(kind="phone", baseline="Ej. 987 654 321", challenger="98765")
    check(out == ("Ej. 987 654 321", "BASELINE_STRUCTURALLY_VALID"), "phone_guard")
    passed += 1

    out = reconcile(kind="email", baseline="", challenger="not-an-email")
    check(out == ("", "NEEDS_REVIEW"), "ambiguous_abstains")
    passed += 1

    out = reconcile(kind="email", baseline="", challenger="a@b.com")
    check(out == ("a@b.com", "CHALLENGER_STRUCTURAL_CORRECTION"), "challenger_can_fill_structurally_valid_missing_baseline")
    passed += 1

    check(structurally_valid("email", "Ej. miguel@correo.com"), "email_validator_positive")
    passed += 1
    check(not structurally_valid("email", "Ej. miguelxcorreo.com"), "email_validator_negative")
    passed += 1

    print(f"PASS_P0_DUAL_OCR_RECONCILIATION_CONTRACT={passed}/12")
    print("RUNTIME_PROMOTED=false")
    print("PRODUCTION_AUTHORIZED=false")
    print("HOLDOUT_ACCESSED=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
