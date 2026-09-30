#!/usr/bin/env python3
"""Deterministic regression for ASSURANCE_EVALUATOR core + thin runner."""
from __future__ import annotations

import copy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from assurance_evaluator_runner_v1 import run_assurance_evaluator  # noqa: E402

SUBJECT_TYPE = "CAPABILITY"
SUBJECT_CODE = "EXAMPLE_CAPABILITY"
REVISION = "a" * 40
CLAIM = "MATERIAL_CLAIM_V1"
OBLIGATION = "OBLIGATION_EXACT_EVIDENCE_V1"
DEFEATER = "DEFEATER_NEGATIVE_PATH_V1"
BINDING = "BIND-EXAMPLE-CAPABILITY-MATERIAL-CLAIM-V1"
JUDGE = "00000000-0000-0000-0000-000000000001"


def router(*, applicable: bool = True, subject_code: str = SUBJECT_CODE) -> dict:
    return {
        "schema_version": "lf-assurance-router-decision/v1",
        "applicability_authority": "CHANGESET_GOVERNANCE_LF_V1",
        "assurance_applicable": applicable,
        "subject_type": SUBJECT_TYPE,
        "subject_code": subject_code,
        "subject_revision": REVISION,
        "decision_ref": "pase-plan://example/assurance",
    }


def binding(*, code: str = BINDING, subject_code: str = SUBJECT_CODE, status: str = "ACTIVE") -> dict:
    return {
        "binding_code": code,
        "subject_type": SUBJECT_TYPE,
        "subject_code": subject_code,
        "standard_claim_code": CLAIM,
        "standard_claim_version": 1,
        "status": status,
    }


def claim(*, status: str = "ACTIVE", closure_rule: dict | None = None) -> dict:
    return {
        "claim_code": CLAIM,
        "claim_version": 1,
        "subject_type": SUBJECT_TYPE,
        "subject_code": SUBJECT_CODE,
        "status": status,
        "closure_rule": closure_rule if closure_rule is not None else {"open_defeater_blocks_pass": True},
    }


def obligation(*, verification_method: str = "DETERMINISTIC", status: str = "ACTIVE") -> dict:
    return {
        "obligation_code": OBLIGATION,
        "claim_code": CLAIM,
        "claim_version": 1,
        "required": True,
        "status": status,
        "verification_method": verification_method,
    }


def defeater(*, closed: bool = True, status: str = "ACTIVE") -> dict:
    return {
        "defeater_code": DEFEATER,
        "claim_code": CLAIM,
        "claim_version": 1,
        "mandatory": True,
        "status": status,
        "closed": closed,
    }


def evidence(
    *,
    result: str = "PASS",
    revision: str = REVISION,
    durable: bool = True,
    zero_effect: bool = False,
    judge_result_id: str | None = None,
) -> dict:
    return {
        "evidence_ref": "evidence://exact/example",
        "obligation_code": OBLIGATION,
        "subject_revision": revision,
        "result": result,
        "durable": durable,
        "zero_effect_proven": zero_effect,
        "judge_result_id": judge_result_id,
    }


def review(*, mode: str = "NEW_REVIEW_REFERENCE", review_type: str = "INDEPENDENT_REVIEW", judge_id: str = JUDGE) -> dict:
    return {
        "schema_version": "lf-assurance-evaluator-review-reference/v1",
        "mode": mode,
        "review_type": review_type,
        "judge_source": "public.lf_test_judge_results",
        "judge_result_id": judge_id,
        "judge_write_requested": False,
    }


def packet() -> dict:
    return {
        "schema_version": "lf-assurance-evaluator-runner-request/v1",
        "router_decision": router(),
        "subject_bindings": [binding()],
        "claim": claim(),
        "obligations": [obligation()],
        "defeaters": [defeater()],
        "evidence": [evidence()],
        "review_references": [],
    }


def evaluated_result(p: dict) -> str:
    out = run_assurance_evaluator(p)
    assert out["status"] == "EVALUATED", out
    assert out["execute_assurance"] is True, out
    return out["evaluator_result"]["result"]


def main() -> None:
    checks = 0

    # 1. Exact ACTIVE binding + durable exact-revision evidence + closed defeater => PASS.
    p = packet()
    assert evaluated_result(p) == "PASS"
    checks += 1

    # 2. Router N/A => no evaluator execution.
    p = packet()
    p["router_decision"] = router(applicable=False)
    out = run_assurance_evaluator(p)
    assert out["status"] == "NOT_APPLICABLE_NO_EXECUTION" and out["execute_assurance"] is False, out
    checks += 1

    # 3. No ACTIVE exact binding => no evaluator execution.
    p = packet()
    p["subject_bindings"] = [binding(status="CANDIDATO")]
    out = run_assurance_evaluator(p)
    assert out["status"] == "NOT_APPLICABLE_NO_EXECUTION" and out["execute_assurance"] is False, out
    checks += 1

    # 4. ACTIVE wildcard binding fails closed.
    p = packet()
    p["subject_bindings"] = [binding(subject_code="*")]
    out = run_assurance_evaluator(p)
    assert out["status"] == "BLOCKED" and out["reason_code"] == "BLOCKED_NON_EXACT_ACTIVE_BINDING", out
    checks += 1

    # 5. Ambiguous exact ACTIVE bindings fail closed.
    p = packet()
    p["subject_bindings"] = [binding(code="BIND-A"), binding(code="BIND-B")]
    out = run_assurance_evaluator(p)
    assert out["status"] == "BLOCKED" and out["reason_code"] == "BLOCKED_AMBIGUOUS_ACTIVE_BINDING", out
    checks += 1

    # 6. Evidence from another revision cannot prove the claim.
    p = packet()
    p["evidence"] = [evidence(revision="b" * 40)]
    assert evaluated_result(p) == "UNPROVEN"
    checks += 1

    # 7. Non-durable evidence cannot prove the claim.
    p = packet()
    p["evidence"] = [evidence(durable=False)]
    assert evaluated_result(p) == "UNPROVEN"
    checks += 1

    # 8. Durable FAIL dominates.
    p = packet()
    p["evidence"] = [evidence(result="FAIL")]
    assert evaluated_result(p) == "FAIL"
    checks += 1

    # 9. Durable OPEN remains OPEN.
    p = packet()
    p["evidence"] = [evidence(result="OPEN")]
    assert evaluated_result(p) == "OPEN"
    checks += 1

    # 10. Existing false-PASS signal cannot become PASS.
    p = packet()
    p["evidence"] = [evidence(result="FALSE_PASS_RISK")]
    assert evaluated_result(p) == "FALSE_PASS_RISK"
    checks += 1

    # 11. Mandatory open defeater blocks material PASS.
    p = packet()
    p["defeaters"] = [defeater(closed=False)]
    assert evaluated_result(p) == "FALSE_PASS_RISK"
    checks += 1

    # 12. Unsupported closure semantics fail closed to UNPROVEN.
    p = packet()
    p["claim"] = claim(closure_rule={"required_cases": ["T-1"]})
    assert evaluated_result(p) == "UNPROVEN"
    checks += 1

    # 13. Independent-review obligation requires a guarded judge reference.
    p = packet()
    p["obligations"] = [obligation(verification_method="INDEPENDENT_REVIEW")]
    assert evaluated_result(p) == "UNPROVEN"
    checks += 1

    # 14. S36_ASSURANCE is forbidden as a new review reference.
    p = packet()
    p["obligations"] = [obligation(verification_method="INDEPENDENT_REVIEW")]
    p["review_references"] = [review(review_type="S36_ASSURANCE")]
    p["evidence"] = [evidence(judge_result_id=JUDGE)]
    out = run_assurance_evaluator(p)
    assert out["status"] == "BLOCKED" and out["reason_code"] == "BLOCKED_LEGACY_S36_NEW_WRITE_SEMANTICS", out
    checks += 1

    # 15. Historical S36 readback may be consumed only through the existing legacy guard.
    p = packet()
    p["obligations"] = [obligation(verification_method="INDEPENDENT_REVIEW")]
    p["claim"] = claim(closure_rule={"open_defeater_blocks_pass": True, "independent_review_required": True})
    p["review_references"] = [review(mode="HISTORICAL_LEGACY_READBACK", review_type="S36_ASSURANCE")]
    p["evidence"] = [evidence(judge_result_id=JUDGE)]
    out = run_assurance_evaluator(p)
    assert out["status"] == "EVALUATED" and out["evaluator_result"]["result"] == "PASS", out
    assert out["review_decisions"][0]["legacy_readback_only"] is True, out
    checks += 1

    # 16. No required obligations => never infer PASS from an empty model.
    p = packet()
    p["obligations"] = []
    assert evaluated_result(p) == "UNPROVEN"
    checks += 1

    assert checks == 16
    print(f"PASS_ASSURANCE_EVALUATOR_CORE_V1 checks={checks}")


if __name__ == "__main__":
    main()
