#!/usr/bin/env python3
"""Self-test for validate_remediation_output.py. Candidate/read-only; no network or DB."""

from validate_remediation_output import grade


def expect(name, candidate, expected_verdict, expected_error=None):
    result = grade(candidate)
    assert result["verdict"] == expected_verdict, (name, result)
    if expected_error is not None:
        assert expected_error in result["errors"], (name, result)
    return name


def main():
    passed = []

    passed.append(expect(
        "generic_remediation_fails",
        {
            "evaluation_outcome": "NEGATIVE_CONFIRMED",
            "evidence_examined": [{"source_ref": "SCREEN_X", "authority_status": "CURRENT"}],
            "evidence_found": [],
            "exact_gap": "No canonical field is resolved for SCREEN_X",
            "cause_type": "CANONICAL_SOURCE_ABSENT",
            "remediation_action": ["Remediacion abierta"],
            "do_not_do": ["Do not invent a field"],
            "close_when": ["cuando se cierre"],
            "next_owner": "INTERNAL_RESOLVER",
            "human_decision_required": False,
        },
        "FAIL_HARD_GUARD",
        "GENERIC_TERMINAL_REMEDIATION",
    ))

    passed.append(expect(
        "na_without_authority_fails",
        {
            "evaluation_outcome": "NOT_APPLICABLE",
            "positive_authority_ref": "",
            "scope_match": True,
            "reason": "No direct records",
        },
        "FAIL_HARD_GUARD",
        "NOT_APPLICABLE_WITHOUT_POSITIVE_AUTHORITY",
    ))

    passed.append(expect(
        "premature_human_fails",
        {
            "evaluation_outcome": "HUMAN_DECISION_REQUIRED",
            "evidence_found": ["Explicit unresolved reference still exists"],
            "exact_gap": "Resolver has not traversed the reference",
            "remediation_action": ["Ask owner to decide"],
            "do_not_do": ["Do not invent"],
            "close_when": ["A canonical decision exists"],
            "authority_ref": "DECISION_REQUEST_AUTHORITY_X",
            "next_owner": "OWNER",
            "human_decision_required": True,
            "internal_resolution_exhausted": False,
        },
        "FAIL_HARD_GUARD",
        "PREMATURE_HUMAN_DECISION",
    ))

    passed.append(expect(
        "positive_with_unresolved_required_fails",
        {
            "evaluation_outcome": "POSITIVE",
            "evidence_chain": ["RULE_X", "FIELD_X"],
            "authority_basis": ["RULE_X=VIGENTE"],
            "resolved_requirements": ["field"],
            "unresolved_required": ["required_validation"],
            "close_reason": "Field exists",
        },
        "FAIL_HARD_GUARD",
        "POSITIVE_WITH_REQUIRED_DIMENSION_UNRESOLVED",
    ))

    passed.append(expect(
        "actionable_negative_passes",
        {
            "evaluation_outcome": "NEGATIVE_CONFIRMED",
            "evidence_examined": [
                {"source_ref": "RULE_VERIFY_TOKEN", "authority_status": "ACTIVE"},
                {"source_ref": "FIELD_VERIFICATION_TOKEN", "authority_status": "ACTIVE"},
            ],
            "evidence_found": ["RULE_VERIFY_TOKEN.field_code -> FIELD_VERIFICATION_TOKEN"],
            "exact_gap": "FIELDS resolver does not traverse the explicit field_code reference",
            "cause_type": "RESOLVER_MISSED_EXPLICIT_REFERENCE",
            "remediation_action": [
                "Traverse the explicit reference, resolve the active field, then reevaluate all required FIELDS dimensions"
            ],
            "do_not_do": ["Do not create a new field while the explicit canonical reference remains unresolved"],
            "close_when": [
                "FIELD_VERIFICATION_TOKEN is resolved through the scoped active rule and no required FIELDS dimension remains unresolved"
            ],
            "next_owner": "INTERNAL_RESOLVER",
            "human_decision_required": False,
        },
        "PASS",
    ))

    passed.append(expect(
        "authorized_na_passes",
        {
            "evaluation_outcome": "NOT_APPLICABLE",
            "positive_authority_ref": "DEC_PREAUTH_PERMISSION_NA_X",
            "scope_match": True,
            "reason": "Explicit authority states permissions are not applicable before recovery completes",
        },
        "PASS",
    ))

    assert len(passed) == 6
    print("PASS_INPUT_GOV_REMEDIATION_VALIDATOR_SELFTEST=6/6")


if __name__ == "__main__":
    main()
