#!/usr/bin/env python3
"""Fail-closed dual-OCR reconciliation and adversarial routing contract.

Eight SOURCE_BOUND_TECHNICAL_SLICE cases encode only outcomes supported by the
durable microbenchmark; abstract tokens are used where the durable note does
not disclose literal screen text. Twenty-seven SYNTHETIC_ADVERSARIAL fixtures
are regression-only and grant zero real-corpus/P0-5 credit.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
MONEY_RE = re.compile(r"^(?:S/\s*)?\d{1,3}(?:,\d{3})*(?:\.\d{2})?$")
CODE_RE = re.compile(r"^[A-Z]{2}-\d{5}$")
YEAR_RE = re.compile(r"^\d{4}$")
PERCENT_RE = re.compile(r"^\d{1,3}(?:\.\d+)?%$")

SOURCE_BOUND = "SOURCE_BOUND_TECHNICAL_SLICE"
SYNTHETIC = "SYNTHETIC_ADVERSARIAL"


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
    if kind == "money":
        return bool(MONEY_RE.fullmatch(text))
    if kind == "code":
        return bool(CODE_RE.fullmatch(text))
    if kind == "year":
        return bool(YEAR_RE.fullmatch(text))
    if kind == "percent":
        return bool(PERCENT_RE.fullmatch(text))
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

    Confidence values are evidence only; they are never cross-compared.
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


@dataclass(frozen=True)
class Case:
    case_id: str
    source_class: str
    family: str
    kind: str = "text"
    baseline: str = ""
    challenger: str = ""
    detector_class: str = "TEXT"
    omission: bool = False
    truncated_visible: bool = False
    layout_issue: bool = False
    expected_action: str = ""
    expected_value: str = ""


def route(case: Case) -> tuple[str, str]:
    if case.detector_class in {"NON_TEXT_ICON", "DECORATIVE", "QR_BARCODE"}:
        return "", "DISCARD_NON_TEXT_OCR"
    if case.truncated_visible:
        return case.baseline, "VISIBLE_ONLY_NO_COMPLETION"
    if case.layout_issue:
        return case.baseline, "LAYOUT_RECONSTRUCT"
    if case.omission and case.detector_class in {"CONTROL", "TEXT"}:
        return case.challenger, "TARGETED_CROP_REREAD"
    return reconcile(kind=case.kind, baseline=case.baseline, challenger=case.challenger)


CASES = [
    # Durable source-bound outcomes. Sentinels avoid inventing undisclosed literal text.
    Case("REAL-01", SOURCE_BOUND, "accented_name", baseline="NAME_WITH_ACCENTS", challenger="NAME_WITH_ACCENTS", expected_action="EXACT_AGREEMENT", expected_value="NAME_WITH_ACCENTS"),
    Case("REAL-02", SOURCE_BOUND, "document_number", baseline="DOCUMENT_NUMBER", challenger="DOCUMENT_NUMBER", expected_action="EXACT_AGREEMENT", expected_value="DOCUMENT_NUMBER"),
    Case("REAL-03", SOURCE_BOUND, "phone_prefix", kind="phone_prefix", baseline="+51", challenger="+51", expected_action="EXACT_AGREEMENT", expected_value="+51"),
    Case("REAL-04", SOURCE_BOUND, "phone_placeholder", baseline="PHONE_PLACEHOLDER", challenger="PHONE_PLACEHOLDER", expected_action="EXACT_AGREEMENT", expected_value="PHONE_PLACEHOLDER"),
    Case("REAL-05", SOURCE_BOUND, "email_label", baseline="EMAIL_LABEL", challenger="EMAIL_LABEL", expected_action="EXACT_AGREEMENT", expected_value="EMAIL_LABEL"),
    Case("REAL-06", SOURCE_BOUND, "email_at_sign", kind="email", baseline="Ej. miguelxcorreo.com", challenger="Ej. miguel@correo.com", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="Ej. miguel@correo.com"),
    Case("REAL-07", SOURCE_BOUND, "privacy_punctuation", baseline="PRIVACY_SENTENCE.", challenger="PRIVACY_SENTENCE", expected_action="BASELINE_PRESERVED_DISAGREEMENT", expected_value="PRIVACY_SENTENCE."),
    Case("REAL-08", SOURCE_BOUND, "small_footer", baseline="SMALL_FOOTER", challenger="SMALL_FOOTER", expected_action="EXACT_AGREEMENT", expected_value="SMALL_FOOTER"),

    # Synthetic adversarial fixtures: regression only.
    Case("SYN-01", SYNTHETIC, "zero_vs_o_money", kind="money", baseline="S/ 1,O08.00", challenger="S/ 1,008.00", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="S/ 1,008.00"),
    Case("SYN-02", SYNTHETIC, "one_l_code", kind="code", baseline="LF-l0118", challenger="LF-10118", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="LF-10118"),
    Case("SYN-03", SYNTHETIC, "decimal_separator", kind="money", baseline="S/ 2.111,92", challenger="S/ 2,111.92", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="S/ 2,111.92"),
    Case("SYN-04", SYNTHETIC, "tilde_disagreement", baseline="Politica de Privacidad", challenger="Política de Privacidad", expected_action="BASELINE_PRESERVED_DISAGREEMENT", expected_value="Politica de Privacidad"),
    Case("SYN-05", SYNTHETIC, "enye_disagreement", baseline="Ano", challenger="Año", expected_action="BASELINE_PRESERVED_DISAGREEMENT", expected_value="Ano"),
    Case("SYN-06", SYNTHETIC, "small_gray_omission", challenger="Información referencial", omission=True, detector_class="TEXT", expected_action="TARGETED_CROP_REREAD", expected_value="Información referencial"),
    Case("SYN-07", SYNTHETIC, "truncated_privacy", baseline="Política de Privaci…", challenger="Política de Privacidad", truncated_visible=True, expected_action="VISIBLE_ONLY_NO_COMPLETION", expected_value="Política de Privaci…"),
    Case("SYN-08", SYNTHETIC, "disabled_button_omission", challenger="Continuar", omission=True, detector_class="CONTROL", expected_action="TARGETED_CROP_REREAD", expected_value="Continuar"),
    Case("SYN-09", SYNTHETIC, "empty_checkbox_icon", baseline="O", detector_class="NON_TEXT_ICON", expected_action="DISCARD_NON_TEXT_OCR", expected_value=""),
    Case("SYN-10", SYNTHETIC, "checked_checkbox_icon", baseline="V", detector_class="NON_TEXT_ICON", expected_action="DISCARD_NON_TEXT_OCR", expected_value=""),
    Case("SYN-11", SYNTHETIC, "notification_badge", baseline="3", challenger="3", expected_action="EXACT_AGREEMENT", expected_value="3"),
    Case("SYN-12", SYNTHETIC, "lock_icon", baseline="D", detector_class="NON_TEXT_ICON", expected_action="DISCARD_NON_TEXT_OCR", expected_value=""),
    Case("SYN-13", SYNTHETIC, "two_column_order", baseline="Celular Correo", layout_issue=True, expected_action="LAYOUT_RECONSTRUCT", expected_value="Celular Correo"),
    Case("SYN-14", SYNTHETIC, "repeated_labels_ownership", baseline="Monto Monto", layout_issue=True, expected_action="LAYOUT_RECONSTRUCT", expected_value="Monto Monto"),
    Case("SYN-15", SYNTHETIC, "strikethrough_amount", kind="money", baseline="S/ 3,2-00.00", challenger="S/ 3,200.00", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="S/ 3,200.00"),
    Case("SYN-16", SYNTHETIC, "tooltip_layer", baseline="Ayuda Monto", layout_issue=True, expected_action="LAYOUT_RECONSTRUCT", expected_value="Ayuda Monto"),
    Case("SYN-17", SYNTHETIC, "scroll_visibility", baseline="Texto visible…", challenger="Texto visible y contenido fuera del viewport", truncated_visible=True, expected_action="VISIBLE_ONLY_NO_COMPLETION", expected_value="Texto visible…"),
    Case("SYN-18", SYNTHETIC, "illustration_false_text", baseline="10", detector_class="DECORATIVE", expected_action="DISCARD_NON_TEXT_OCR", expected_value=""),
    Case("SYN-19", SYNTHETIC, "responsive_mobile_order", baseline="Nombre DNI Correo", layout_issue=True, expected_action="LAYOUT_RECONSTRUCT", expected_value="Nombre DNI Correo"),
    Case("SYN-20", SYNTHETIC, "qr_false_text", baseline="II0O1I", detector_class="QR_BARCODE", expected_action="DISCARD_NON_TEXT_OCR", expected_value=""),
    Case("SYN-21", SYNTHETIC, "year_o_digit", kind="year", baseline="2O26", challenger="2026", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="2026"),
    Case("SYN-22", SYNTHETIC, "percent_letter_o", kind="percent", baseline="5O%", challenger="50%", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="50%"),
    Case("SYN-23", SYNTHETIC, "valid_money_disagreement", kind="money", baseline="S/ 1,000.00", challenger="S/ 1,008.00", expected_action="BASELINE_PRESERVED_DISAGREEMENT", expected_value="S/ 1,000.00"),
    Case("SYN-24", SYNTHETIC, "valid_code_disagreement", kind="code", baseline="LF-10118", challenger="LF-10119", expected_action="BASELINE_PRESERVED_DISAGREEMENT", expected_value="LF-10118"),
    Case("SYN-25", SYNTHETIC, "ambiguous_missing_email", kind="email", challenger="miguelecorreo.com", expected_action="NEEDS_REVIEW", expected_value=""),
    Case("SYN-26", SYNTHETIC, "email_missing_baseline_valid_challenger", kind="email", challenger="miguel@correo.com", expected_action="CHALLENGER_STRUCTURAL_CORRECTION", expected_value="miguel@correo.com"),
    Case("SYN-27", SYNTHETIC, "generic_valid_disagreement", baseline="baseline", challenger="challenger", expected_action="BASELINE_PRESERVED_DISAGREEMENT", expected_value="baseline"),
]


def check(condition: bool, name: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL_DUAL_OCR_RECONCILIATION:{name}")


def core_invariant_tests() -> int:
    cases = [
        ("exact_agreement", reconcile(kind="email", baseline="Ej. miguel@correo.com", challenger="Ej. miguel@correo.com"), ("Ej. miguel@correo.com", "EXACT_AGREEMENT")),
        ("email_structural_correction", reconcile(kind="email", baseline="Ej. miguelxcorreo.com", challenger="Ej. miguel@correo.com"), ("Ej. miguel@correo.com", "CHALLENGER_STRUCTURAL_CORRECTION")),
        ("preserve_valid_baseline", reconcile(kind="email", baseline="Ej. miguel@correo.com", challenger="Ej. miguelxcorreo.com"), ("Ej. miguel@correo.com", "BASELINE_STRUCTURALLY_VALID")),
        ("both_valid_disagreement", reconcile(kind="text", baseline="Política de Privacidad.", challenger="Política de Privacidad"), ("Política de Privacidad.", "BASELINE_PRESERVED_DISAGREEMENT")),
        ("phone_prefix_guard", reconcile(kind="phone_prefix", baseline="+51", challenger="51"), ("+51", "BASELINE_STRUCTURALLY_VALID")),
        ("document_guard", reconcile(kind="document_number", baseline="Ej. 12345678", challenger="Ej. 1234567"), ("Ej. 12345678", "BASELINE_STRUCTURALLY_VALID")),
        ("phone_guard", reconcile(kind="phone", baseline="Ej. 987 654 321", challenger="98765"), ("Ej. 987 654 321", "BASELINE_STRUCTURALLY_VALID")),
        ("ambiguous_abstains", reconcile(kind="email", baseline="", challenger="not-an-email"), ("", "NEEDS_REVIEW")),
        ("valid_missing_baseline", reconcile(kind="email", baseline="", challenger="a@b.com"), ("a@b.com", "CHALLENGER_STRUCTURAL_CORRECTION")),
    ]
    for name, got, expected in cases:
        check(got == expected, name)
    low_high = reconcile(kind="text", baseline="baseline", challenger="challenger", baseline_confidence=0.01, challenger_confidence=0.99)
    high_low = reconcile(kind="text", baseline="baseline", challenger="challenger", baseline_confidence=0.99, challenger_confidence=0.01)
    check(low_high == high_low == ("baseline", "BASELINE_PRESERVED_DISAGREEMENT"), "confidence_not_cross_calibrated")
    check(structurally_valid("email", "Ej. miguel@correo.com"), "email_validator_positive")
    check(not structurally_valid("email", "Ej. miguelxcorreo.com"), "email_validator_negative")
    return 12


def adversarial_tests() -> tuple[int, int, int]:
    check(len(CASES) == 35, "adversarial_case_count")
    source_bound = synthetic = 0
    for case in CASES:
        got = route(case)
        expected = (case.expected_value, case.expected_action)
        check(got == expected, f"adversarial_{case.case_id}")
        source_bound += case.source_class == SOURCE_BOUND
        synthetic += case.source_class == SYNTHETIC
    check((source_bound, synthetic) == (8, 27), "adversarial_source_split")
    return 35, source_bound, synthetic


def main() -> int:
    core_passed = core_invariant_tests()
    adversarial_passed, source_bound, synthetic = adversarial_tests()
    print(f"PASS_P0_DUAL_OCR_RECONCILIATION_CONTRACT={core_passed}/12")
    print(f"PASS_P0_DUAL_OCR_ADVERSARIAL_CONTRACT={adversarial_passed}/35")
    print(f"SOURCE_BOUND_TECHNICAL_SLICES={source_bound}")
    print(f"SYNTHETIC_ADVERSARIAL_FIXTURES={synthetic}")
    print("REAL_CORPUS_CREDIT=0")
    print("P0_5_CREDIT=0")
    print("RUNTIME_PROMOTED=false")
    print("PRODUCTION_AUTHORIZED=false")
    print("HOLDOUT_ACCESSED=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
