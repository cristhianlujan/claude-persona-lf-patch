#!/usr/bin/env python3
"""Deterministic structural/hard-guard grader for Input Governance remediation outputs.

Candidate/read-only utility. It never reads or writes Supabase and has no canonical authority.
Usage:
  python validate_remediation_output.py candidate.json
  cat candidate.json | python validate_remediation_output.py -
Exit 0 = deterministic PASS; exit 1 = FAIL.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

OUTCOMES = {
    "POSITIVE",
    "NOT_APPLICABLE",
    "NEGATIVE_CONFIRMED",
    "HUMAN_DECISION_REQUIRED",
}

NEGATIVE_REQUIRED = {
    "evaluation_outcome",
    "evidence_examined",
    "evidence_found",
    "exact_gap",
    "cause_type",
    "remediation_action",
    "do_not_do",
    "close_when",
    "next_owner",
    "human_decision_required",
}

POSITIVE_REQUIRED = {
    "evaluation_outcome",
    "evidence_chain",
    "authority_basis",
    "resolved_requirements",
    "unresolved_required",
    "close_reason",
}

NA_REQUIRED = {
    "evaluation_outcome",
    "positive_authority_ref",
    "scope_match",
    "reason",
}

HUMAN_REQUIRED = {
    "evaluation_outcome",
    "evidence_found",
    "exact_gap",
    "remediation_action",
    "do_not_do",
    "close_when",
    "authority_ref",
    "next_owner",
    "human_decision_required",
}

GENERIC_PATTERNS = [
    r"^remediaci[oó]n abierta[.!]?$",
    r"^revisar(?: evidencia)?[.!]?$",
    r"^investigar[.!]?$",
    r"^completar(?: la)? informaci[oó]n(?: faltante)?[.!]?$",
    r"^mantener en cola[.!]?$",
    r"^resolver pendiente[.!]?$",
    r"^crear lo faltante[.!]?$",
    r"^keep_in_internal_remediation_queue$",
    r"^resolve_pending_source_or_evidence_internally$",
]

TAUTOLOGICAL_CLOSE = [
    r"^cuando se cierre(?: el gap)?[.!]?$",
    r"^cuando est[eé] listo[.!]?$",
    r"^when (?:the )?gap is closed[.!]?$",
]

ALLOWED_CAUSE_TYPES = {
    "RESOLVER_MISSED_EXPLICIT_REFERENCE",
    "CANONICAL_SOURCE_ABSENT",
    "AUTHORITY_INSUFFICIENT",
    "SOURCE_CONFLICT",
    "STALE_EVIDENCE",
    "APPLICABILITY_AUTHORITY_MISSING",
    "LATER_STAGE_REQUIREMENT",
    "FUNCTIONAL_DEFINITION_MISSING",
    "GOVERNANCE_EVIDENCE_MISSING",
    "HUMAN_AUTHORITY_REQUIRED",
}


def fail(errors: list[str], code: str) -> None:
    if code not in errors:
        errors.append(code)


def nonempty_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def nonempty_list(value: Any) -> bool:
    return isinstance(value, list) and len(value) > 0


def text_values(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [x for x in value if isinstance(x, str)]
    return []


def matches_any(value: str, patterns: list[str]) -> bool:
    normalized = value.strip().lower()
    return any(re.fullmatch(pattern, normalized, flags=re.IGNORECASE) for pattern in patterns)


def grade(candidate: Any) -> dict[str, Any]:
    errors: list[str] = []
    if not isinstance(candidate, dict):
        return {"verdict": "FAIL_HARD_GUARD", "errors": ["OUTPUT_NOT_OBJECT"]}

    outcome = candidate.get("evaluation_outcome")
    if outcome not in OUTCOMES:
        fail(errors, "INVALID_OR_MISSING_TERMINAL_OUTCOME")
        return {"verdict": "FAIL_OUTCOME", "errors": errors}

    if candidate.get("unsupported_invention") is True:
        fail(errors, "UNSUPPORTED_INVENTION")
    if candidate.get("candidate_or_stale_used_as_current_authority") is True:
        fail(errors, "NONCURRENT_AUTHORITY_USED_AS_CURRENT")
    if candidate.get("cross_scope_authority_leakage") is True:
        fail(errors, "CROSS_SCOPE_AUTHORITY_LEAKAGE")
    if candidate.get("keyword_or_category_used_as_sufficiency_authority") is True:
        fail(errors, "KEYWORD_AS_SUFFICIENCY_AUTHORITY")

    if outcome == "NEGATIVE_CONFIRMED":
        missing = sorted(NEGATIVE_REQUIRED - set(candidate))
        for key in missing:
            fail(errors, f"MISSING_REQUIRED:{key}")
        if candidate.get("cause_type") not in ALLOWED_CAUSE_TYPES:
            fail(errors, "INVALID_CAUSE_TYPE")
        if not nonempty_list(candidate.get("evidence_examined")):
            fail(errors, "EVIDENCE_EXAMINED_EMPTY")
        if not isinstance(candidate.get("evidence_found"), list):
            fail(errors, "EVIDENCE_FOUND_NOT_ARRAY")
        if not nonempty_text(candidate.get("exact_gap")):
            fail(errors, "EXACT_GAP_EMPTY")
        if not nonempty_list(candidate.get("remediation_action")):
            fail(errors, "REMEDIATION_ACTION_EMPTY")
        if not nonempty_list(candidate.get("do_not_do")):
            fail(errors, "DO_NOT_DO_EMPTY")
        if not nonempty_list(candidate.get("close_when")):
            fail(errors, "CLOSE_WHEN_EMPTY")
        if not nonempty_text(candidate.get("next_owner")):
            fail(errors, "NEXT_OWNER_EMPTY")
        if candidate.get("human_decision_required") not in (True, False):
            fail(errors, "HUMAN_DECISION_FLAG_INVALID")
        for value in text_values(candidate.get("remediation_action")):
            if matches_any(value, GENERIC_PATTERNS):
                fail(errors, "GENERIC_TERMINAL_REMEDIATION")
        for value in text_values(candidate.get("close_when")):
            if matches_any(value, TAUTOLOGICAL_CLOSE):
                fail(errors, "TAUTOLOGICAL_CLOSE_CONDITION")

    elif outcome == "POSITIVE":
        for key in sorted(POSITIVE_REQUIRED - set(candidate)):
            fail(errors, f"MISSING_REQUIRED:{key}")
        if not nonempty_list(candidate.get("evidence_chain")):
            fail(errors, "EVIDENCE_CHAIN_EMPTY")
        if not nonempty_list(candidate.get("authority_basis")):
            fail(errors, "AUTHORITY_BASIS_EMPTY")
        if not nonempty_list(candidate.get("resolved_requirements")):
            fail(errors, "RESOLVED_REQUIREMENTS_EMPTY")
        unresolved = candidate.get("unresolved_required")
        if not isinstance(unresolved, list):
            fail(errors, "UNRESOLVED_REQUIRED_NOT_ARRAY")
        elif unresolved:
            fail(errors, "POSITIVE_WITH_REQUIRED_DIMENSION_UNRESOLVED")
        if not nonempty_text(candidate.get("close_reason")):
            fail(errors, "CLOSE_REASON_EMPTY")

    elif outcome == "NOT_APPLICABLE":
        for key in sorted(NA_REQUIRED - set(candidate)):
            fail(errors, f"MISSING_REQUIRED:{key}")
        if not nonempty_text(candidate.get("positive_authority_ref")):
            fail(errors, "NOT_APPLICABLE_WITHOUT_POSITIVE_AUTHORITY")
        if candidate.get("scope_match") is not True:
            fail(errors, "NOT_APPLICABLE_SCOPE_NOT_PROVEN")
        if not nonempty_text(candidate.get("reason")):
            fail(errors, "NOT_APPLICABLE_REASON_EMPTY")

    elif outcome == "HUMAN_DECISION_REQUIRED":
        for key in sorted(HUMAN_REQUIRED - set(candidate)):
            fail(errors, f"MISSING_REQUIRED:{key}")
        if candidate.get("human_decision_required") is not True:
            fail(errors, "HUMAN_DECISION_FLAG_NOT_TRUE")
        if not nonempty_text(candidate.get("authority_ref")):
            fail(errors, "HUMAN_DECISION_AUTHORITY_MISSING")
        if candidate.get("internal_resolution_exhausted") is not True:
            fail(errors, "PREMATURE_HUMAN_DECISION")
        if not nonempty_list(candidate.get("remediation_action")):
            fail(errors, "HUMAN_DECISION_ACTION_EMPTY")
        if not nonempty_list(candidate.get("close_when")):
            fail(errors, "HUMAN_DECISION_CLOSE_WHEN_EMPTY")

    verdict = "PASS" if not errors else "FAIL_HARD_GUARD"
    return {"verdict": verdict, "evaluation_outcome": outcome, "errors": errors}


def main() -> int:
    if len(sys.argv) != 2:
        print(json.dumps({"verdict": "FAIL_HARD_GUARD", "errors": ["USAGE: candidate.json|-"],}, ensure_ascii=False))
        return 1
    raw = sys.stdin.read() if sys.argv[1] == "-" else Path(sys.argv[1]).read_text(encoding="utf-8")
    try:
        candidate = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(json.dumps({"verdict": "FAIL_HARD_GUARD", "errors": [f"INVALID_JSON:{exc.msg}"]}, ensure_ascii=False))
        return 1
    result = grade(candidate)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
