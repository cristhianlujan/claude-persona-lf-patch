#!/usr/bin/env python3
"""Regression for evidence-carrier and cross-family fail-closed invariants.

V7 preserves every V6 invariant and adds independent reproductions from the
fresh PR166 audit (AUD-026/AUD-027). It does not broaden the empirically proven
mask alphabet: unsupported glyph families remain an explicit limitation rather
than being reclassified as masks without source evidence.
"""
from __future__ import annotations

import json

import P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V6 as v6
import P0_SELECTIVE_OCR_ROUTER_V4 as router


def t_attempt(variant_id: str, text: str, profile: str = "eng") -> dict:
    return {
        "engine_family": "TESSERACT",
        "variant_id": variant_id,
        "text": text,
        "language_profile": profile,
    }


def p_attempt(variant_id: str, text: str) -> dict:
    return {
        "engine_family": "PADDLE",
        "variant_id": variant_id,
        "text": text,
    }


def _base_targeted(attempts: list[dict]) -> dict:
    return {
        "materiality": "TEXT",
        "kind": "email",
        "baseline_text": "bad-email",
        "targeted_attempts": attempts,
        "challenger_allowed": True,
    }


def _paddle_required_observation() -> dict:
    return _base_targeted([
        t_attempt("t1", "tucorreoOemail.com", "eng"),
        t_attempt("t2", "tucorreo0email.com", "spa"),
    ])


def main() -> int:
    if v6.main() != 0:
        raise SystemExit("FAIL_V6_PREREQUISITE")

    checks: dict[str, bool] = {}

    # AUD-026: lack of a stable identity cannot erase material mask evidence.
    empty_mask = router.route_observation(_base_targeted([
        t_attempt("u1", "alpha@example.com", "eng"),
        t_attempt("u2", "alpha@example.com", "spa"),
        t_attempt("", "jus***@gmail.com", "eng"),
    ]))
    checks["empty_id_can_carry_mask_evidence"] = (
        empty_mask.get("decision") == "VISIBLE_MASKED_NO_COMPLETION"
        and empty_mask.get("resolved") is False
        and empty_mask.get("invoke_paddle") is False
    )

    whitespace_mask = router.route_observation(_base_targeted([
        t_attempt("u1", "alpha@example.com", "eng"),
        t_attempt("u2", "alpha@example.com", "spa"),
        t_attempt("   ", "ju•@gmail.com", "eng"),
    ]))
    checks["whitespace_id_can_carry_mask_evidence"] = (
        whitespace_mask.get("decision") == "VISIBLE_MASKED_NO_COMPLETION"
        and whitespace_mask.get("resolved") is False
    )

    # An unidentifiable clean attempt must not manufacture an identity conflict.
    empty_clean = router.route_observation(_base_targeted([
        t_attempt("u1", "alpha@example.com", "eng"),
        t_attempt("u2", "alpha@example.com", "spa"),
        t_attempt("", "beta@example.com", "eng"),
    ]))
    checks["empty_id_clean_attempt_no_artificial_conflict"] = (
        empty_clean.get("decision") != "EVIDENCE_VARIANT_ID_CONFLICT"
    )

    # AUD-027: a stable ID is global evidence identity, not family-local identity.
    cross_family_conflict = router.route_observation(_base_targeted([
        t_attempt("dup", "alpha@example.com", "eng"),
        t_attempt("u2", "alpha@example.com", "spa"),
        p_attempt("dup", "jus***@gmail.com"),
    ]))
    checks["cross_family_duplicate_payload_conflict"] = (
        cross_family_conflict.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and cross_family_conflict.get("resolved") is False
        and cross_family_conflict.get("invoke_paddle") is False
    )

    cross_family_same = router.route_observation(_base_targeted([
        t_attempt("dup", "alpha@example.com", "eng"),
        t_attempt("u2", "alpha@example.com", "spa"),
        p_attempt("dup", "alpha@example.com"),
    ]))
    checks["cross_family_same_text_not_false_conflict"] = (
        cross_family_same.get("decision") != "EVIDENCE_VARIANT_ID_CONFLICT"
    )

    # Mask evidence is material even when carried by a non-consumed family.
    cross_family_mask = router.route_observation(_base_targeted([
        t_attempt("u1", "alpha@example.com", "eng"),
        t_attempt("u2", "alpha@example.com", "spa"),
        p_attempt("p9", "jus***@gmail.com"),
    ]))
    checks["cross_family_mask_evidence_blocks_targeted_accept"] = (
        cross_family_mask.get("decision") == "VISIBLE_MASKED_NO_COMPLETION"
        and cross_family_mask.get("resolved") is False
    )

    # Cross-family identity conflict must also be checked when Paddle attempts
    # arrive through reconcile_paddle rather than targeted_attempts.
    paddle_cross_family = router.reconcile_paddle(
        _paddle_required_observation(),
        [p_attempt("t1", "alpha@example.com"), p_attempt("p2", "alpha@example.com")],
    )
    checks["paddle_reconcile_cross_family_id_conflict"] = (
        paddle_cross_family.get("decision") == "EVIDENCE_VARIANT_ID_CONFLICT"
        and paddle_cross_family.get("resolved") is False
    )

    paddle_empty_mask = router.reconcile_paddle(
        _paddle_required_observation(),
        [p_attempt("", "jus***@gmail.com"), p_attempt("p2", "alpha@example.com"), p_attempt("p3", "alpha@example.com")],
    )
    checks["paddle_empty_id_mask_evidence_blocks"] = (
        paddle_empty_mask.get("decision") == "PADDLE_MASKED_NO_COMPLETION"
        and paddle_empty_mask.get("resolved") is False
    )

    # AUD-03 owner-safe disposition: no unsupported glyph is silently promoted
    # to a newly claimed mask family. The limitation must remain explicit until
    # source-bound evidence supports a broader rule.
    unsupported = [
        "ju●●●@gmail.com",
        "ju███@gmail.com",
        "juXXX@gmail.com",
        "ju###@gmail.com",
        "ju…@gmail.com",
        "ju∗∗∗@gmail.com",
        "ju**@gmail.com",
    ]
    checks["unsupported_mask_glyphs_not_reclassified_without_evidence"] = all(
        router.is_masked_structured_text(value) is False for value in unsupported
    )

    failed = sorted(name for name, ok in checks.items() if not ok)
    result = {
        "gate": "PASS_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V7" if not failed else "FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V7",
        "check_count": len(checks),
        "failed": failed,
        "checks": checks,
        "remediated_findings": ["AUD-026", "AUD-027"],
        "accepted_explicit_limitation": "AUD-03_UNSUPPORTED_MASK_GLYPHS_REQUIRE_SOURCE_BOUND_EVIDENCE",
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "production_authorized": False,
        "sealed_holdout_accessed": False,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    if failed:
        raise SystemExit("FAIL_P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_V7:" + ",".join(failed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
