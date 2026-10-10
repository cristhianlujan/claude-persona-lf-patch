"""M9.8 authored negative check: reuse pure canonical CLOSURE_GATE, never dispatch POST_PASE.

The fixture builder belongs to existing repository tests and is not a source of
live IG evidence. Live M9.8 bundle/field admission is independently read from
the sandbox DB; this test proves the generic closure semantic only.
"""
from __future__ import annotations

import json
from sandbox.lf_contract_gate_test.closure_gate.closure_gate_v1 import (
    ClosureGateBlocked,
    build_closure_verdict,
)
from sandbox.lf_contract_gate_test.closure_gate.test_closure_gate_v1 import (
    base_request,
    waiver_for,
)

TEST_CODE = "ENG_M9_8_GATE_FAIL_NEGATIVE"


def run() -> dict:
    # Positive control prevents an always-BLOCKED implementation from passing.
    positive = build_closure_verdict(base_request(("PASS", "PASS")))
    assert positive["verdict"] == "PASS"
    assert positive["terminal_status"] == "CLOSED"

    checked = 0
    for outcomes, expected in (
        (("FAIL", "PASS"), "FAIL"),
        (("BLOCKED", "PASS"), "BLOCKED"),
        (("PASS", "FAIL"), "FAIL"),
        (("PASS", "BLOCKED"), "BLOCKED"),
        (("FAIL", "BLOCKED"), "BLOCKED"),
    ):
        observed = build_closure_verdict(base_request(outcomes))
        assert observed["verdict"] == expected, (outcomes, observed)
        assert observed["verdict"] != "PASS"
        assert observed["terminal_status"] == "NOT_CLOSED"
        assert observed["evidence_collection_performed"] is False
        assert observed["control_execution_performed"] is False
        assert observed["promotion_performed"] is False
        assert observed["lifecycle_mutation_performed"] is False
        checked += 1

    blocked_request = base_request(("BLOCKED", "PASS"))
    blocked_request["waiver_receipts"] = [
        waiver_for(blocked_request, "AUTHORITY_READBACK")
    ]
    try:
        build_closure_verdict(blocked_request)
    except ClosureGateBlocked as exc:
        assert str(exc) == "WAIVER_FOR_BLOCKED_CONTROL_FORBIDDEN", str(exc)
    else:
        raise AssertionError("BLOCKED control illegally waived")
    checked += 1

    assert positive["schema_version"] == "LF_POST_PASE_CLOSURE_VERDICT_V1"
    assert checked == 6
    return {
        "schema_version": "ENGINEERING_AUTHORED_NEGATIVE_TEST_V1",
        "status": "PASS",
        "test_code": TEST_CODE,
        "observed": {
            "test_passed": True,
            "test_exit_code": 0,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "positive_count": 1,
            "negative_count": checked,
            "source": "CANONICAL_CLOSURE_GATE_PURE_FUNCTION",
            "cross_workstream_execution": False,
        },
    }


if __name__ == "__main__":
    print(json.dumps(run(), sort_keys=True))
