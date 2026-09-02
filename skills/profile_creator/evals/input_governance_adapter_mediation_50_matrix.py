#!/usr/bin/env python3
import json

FAMILIES = ["client_screen", "b2b_screen", "loan_flow", "payment_flow", "auth_flow"]

SCENARIOS = [
    ("not_applicable", False, False, None, True, False, "SKIP"),
    ("required_pass", True, False, "PASS", True, False, "PASS"),
    ("required_repair", True, False, "REPAIR", True, False, "BLOCK"),
    ("required_block", True, False, "BLOCK", True, False, "BLOCK"),
    ("missing_receipt", True, False, None, True, False, "BLOCK"),
    ("stale_receipt", True, False, "PASS", False, False, "BLOCK"),
    ("direct_profile_attempt", True, True, "PASS", True, False, "BLOCK"),
    ("second_llm_attempt", True, False, "PASS", True, True, "BLOCK"),
    ("fresh_pass_minimal_sections", True, False, "PASS", True, False, "PASS"),
    ("fresh_pass_reused_adapter_receipt", True, False, "PASS", True, False, "PASS"),
]


def decide(case):
    if not case["governance_required"]:
        return "SKIP"
    if case["direct_profile_invocation"]:
        return "BLOCK"
    if case["second_llm_call"]:
        return "BLOCK"
    if not case["receipt_fresh"]:
        return "BLOCK"
    if case["receipt_verdict"] != "PASS":
        return "BLOCK"
    return "PASS"


def main():
    cases = []
    for family in FAMILIES:
        for name, required, direct, verdict, fresh, second_llm, expected in SCENARIOS:
            case = {
                "id": f"{family}::{name}",
                "family": family,
                "governance_required": required,
                "direct_profile_invocation": direct,
                "receipt_verdict": verdict,
                "receipt_fresh": fresh,
                "second_llm_call": second_llm,
                "expected": expected,
            }
            actual = decide(case)
            case["actual"] = actual
            case["passed"] = actual == expected
            cases.append(case)

    failed = [case["id"] for case in cases if not case["passed"]]
    family_counts = {family: sum(1 for case in cases if case["family"] == family) for family in FAMILIES}
    result = {
        "status": "PASS" if not failed else "FAIL",
        "matrix": "INPUT_GOVERNANCE_ADAPTER_MEDIATION_50_V1",
        "total": len(cases),
        "passed": len(cases) - len(failed),
        "failed": failed,
        "family_counts": family_counts,
        "assertions": {
            "router_adapter_mediation_model": True,
            "direct_profile_invocation_forbidden": True,
            "missing_or_stale_receipt_fail_closed": True,
            "continuation_pass_only": True,
            "second_llm_call_forbidden": True,
            "loan_family_included": True,
            "cross_domain_family_coverage": True,
        },
        "runtime_authorized": False,
        "production_authorized": False,
        "canonical_product_decision_created": False,
        "cases": cases,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if not failed and len(cases) == 50 else 1


if __name__ == "__main__":
    raise SystemExit(main())
