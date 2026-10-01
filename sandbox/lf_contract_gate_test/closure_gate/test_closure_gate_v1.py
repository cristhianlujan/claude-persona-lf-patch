from __future__ import annotations

import copy
import inspect

from sandbox.lf_contract_gate_test.closure_gate.closure_gate_v1 import (
    ClosureGateBlocked,
    build_closure_verdict,
    closure_request_digest,
)
from sandbox.lf_contract_gate_test.post_pase_final_evidence.final_evidence_v1 import (
    build_final_evidence_manifest,
    controls_digest,
    outcome_binding_digest,
)
import sandbox.lf_contract_gate_test.closure_gate.closure_gate_v1 as closure_source

PLAN_DIGEST = "a" * 64
MERGE_SHA = "b" * 40


def typed(receipt_id, receipt_sha, outcome):
    return {
        "schema_version": "LF_TYPED_CONTROL_TERMINAL_RECEIPT_V1",
        "validation_decision": "TYPED_RECEIPT_VALIDATED",
        "receipt_id": receipt_id,
        "receipt_sha256": receipt_sha,
        "terminal_outcome": outcome,
        "outcome_binding_sha256": outcome_binding_digest(receipt_id, receipt_sha, outcome),
    }


def final_manifest(outcomes):
    controls = [
        {"control_code": "AUTHORITY_READBACK", "disposition": "REQUIRED"},
        {"control_code": "GITHUB_RECONCILIATION", "disposition": "REQUIRED"},
        {"control_code": "RUNTIME_DEPLOY_VERIFICATION", "disposition": "NOT_APPLICABLE"},
    ]
    receipts = []
    for i, (code, outcome) in enumerate(
        [("AUTHORITY_READBACK", outcomes[0]), ("GITHUB_RECONCILIATION", outcomes[1])], start=1
    ):
        rid = f"{i}{i}{i}{i}{i}{i}{i}{i}-1111-1111-1111-11111111111{i}"
        sha = str(i) * 64
        receipts.append(
            {
                "control_code": code,
                "receipt_id": rid,
                "receipt_sha256": sha,
                "execution_id": f"CTRL-EXEC-00{i}",
                "capability_code": code,
                "gate_code": code,
                "source_head_sha": MERGE_SHA,
                "subject_ref": "github://repo@" + MERGE_SHA + "/" + code.lower(),
                "subject_sha256": str(i + 3) * 64,
                "authority_ref": "authority://" + code.lower(),
                "resolver_id": "TRUSTED_RESOLVER_V1",
                "verification_state": "VERIFIED",
                "plan_digest": PLAN_DIGEST,
                "typed_receipt": typed(rid, sha, outcome),
            }
        )
    return build_final_evidence_manifest(
        {
            "post_pase_execution_id": "POST-PASE-EXEC-001",
            "orchestrator_execution_id": "ORCH-EXEC-001",
            "plan_id": "POST-PASE-PLAN-001",
            "plan_digest": PLAN_DIGEST,
            "merge_sha": MERGE_SHA,
            "orchestrator_entry": {
                "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
                "orchestrator_execution_id": "ORCH-EXEC-001",
                "plan_digest": PLAN_DIGEST,
                "capability_code": "FINAL_EVIDENCE",
            },
            "controls": controls,
            "plan_authority_receipt": {
                "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
                "decision": "AUTHORIZED_DELTA",
                "plan_id": "POST-PASE-PLAN-001",
                "plan_digest": PLAN_DIGEST,
                "controls_digest": controls_digest(controls),
            },
            "receipts": receipts,
        }
    )


def base_request(outcomes=("PASS", "PASS")):
    controls = [
        {"control_code": "AUTHORITY_READBACK", "disposition": "REQUIRED"},
        {"control_code": "GITHUB_RECONCILIATION", "disposition": "REQUIRED"},
        {"control_code": "RUNTIME_DEPLOY_VERIFICATION", "disposition": "NOT_APPLICABLE"},
    ]
    return {
        "post_pase_execution_id": "POST-PASE-EXEC-001",
        "orchestrator_execution_id": "ORCH-EXEC-001",
        "plan_id": "POST-PASE-PLAN-001",
        "plan_digest": PLAN_DIGEST,
        "merge_sha": MERGE_SHA,
        "orchestrator_entry": {
            "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
            "orchestrator_execution_id": "ORCH-EXEC-001",
            "plan_digest": PLAN_DIGEST,
            "capability_code": "CLOSURE_GATE",
        },
        "plan_controls": controls,
        "plan_authority_receipt": {
            "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
            "decision": "AUTHORIZED_DELTA",
            "plan_id": "POST-PASE-PLAN-001",
            "plan_digest": PLAN_DIGEST,
            "controls_digest": controls_digest(controls),
        },
        "final_evidence_manifest": final_manifest(outcomes),
        "waiver_receipts": [],
    }


def waiver_for(req, control):
    digest = closure_request_digest(req, req["final_evidence_manifest"])
    return {
        "schema_version": "LF_WAIVER_AUTHORITY_RECEIPT_V1",
        "decision": "WAIVER_AUTHORIZED",
        "post_pase_execution_id": req["post_pase_execution_id"],
        "control_id": control,
        "plan_digest": req["plan_digest"],
        "merge_sha": req["merge_sha"],
        "consumer_request_digest": digest,
        "grant_sha256": "c" * 64,
        "consumption_readback_digest": "d" * 64,
    }


def blocked(req, expected):
    try:
        build_closure_verdict(req)
    except ClosureGateBlocked as exc:
        assert str(exc) == expected, (str(exc), expected)
        return
    raise AssertionError(f"expected block {expected}")


def main():
    checks = 0

    req = base_request(("PASS", "PASS"))
    out = build_closure_verdict(req)
    assert out["verdict"] == "PASS" and out["terminal_status"] == "CLOSED"
    assert out["evidence_collection_performed"] is False
    assert out["control_execution_performed"] is False
    checks += 4

    req = base_request(("FAIL", "PASS"))
    out = build_closure_verdict(req)
    assert out["verdict"] == "FAIL" and out["terminal_status"] == "NOT_CLOSED"
    checks += 2

    req = base_request(("BLOCKED", "PASS"))
    out = build_closure_verdict(req)
    assert out["verdict"] == "BLOCKED" and out["terminal_status"] == "NOT_CLOSED"
    checks += 2

    req = base_request(("FAIL", "PASS"))
    req["waiver_receipts"] = [waiver_for(req, "AUTHORITY_READBACK")]
    out = build_closure_verdict(req)
    assert out["verdict"] == "WAIVED" and out["terminal_status"] == "CLOSED"
    assert out["waived_controls"] == ["AUTHORITY_READBACK"]
    checks += 3

    req = base_request(("FAIL", "FAIL"))
    req["waiver_receipts"] = [waiver_for(req, "AUTHORITY_READBACK")]
    out = build_closure_verdict(req)
    assert out["verdict"] == "FAIL"
    checks += 1

    req = base_request(("PASS", "PASS"))
    req["waiver_receipts"] = [{
        "schema_version": "LF_WAIVER_AUTHORITY_RECEIPT_V1",
        "decision": "WAIVER_AUTHORIZED",
    }]
    blocked(req, "EXTRA_WAIVER_WITHOUT_FAILED_CONTROL"); checks += 1

    req = base_request(("BLOCKED", "PASS"))
    req["waiver_receipts"] = [{
        "schema_version": "LF_WAIVER_AUTHORITY_RECEIPT_V1",
        "decision": "WAIVER_AUTHORIZED",
    }]
    blocked(req, "WAIVER_FOR_BLOCKED_CONTROL_FORBIDDEN"); checks += 1

    req = base_request(("FAIL", "PASS"))
    fake = waiver_for(req, "AUTHORITY_READBACK")
    fake["schema_version"] = "LF_EVENT_VALIDATION_EXEMPTION_V2"
    req["waiver_receipts"] = [fake]
    blocked(req, "WAIVER_RECEIPT_SCHEMA"); checks += 1

    req = base_request(("FAIL", "PASS"))
    fake = waiver_for(req, "AUTHORITY_READBACK")
    fake["decision"] = "WAIVER_BLOCKED"
    req["waiver_receipts"] = [fake]
    blocked(req, "WAIVER_NOT_AUTHORIZED"); checks += 1

    req = base_request(("FAIL", "PASS"))
    fake = waiver_for(req, "AUTHORITY_READBACK")
    fake["consumer_request_digest"] = "e" * 64
    req["waiver_receipts"] = [fake]
    blocked(req, "WAIVER_REQUEST_DIGEST_MISMATCH"); checks += 1

    req = base_request(("PASS", "PASS"))
    req["final_evidence_manifest"]["receipt_refs"][0]["terminal_outcome"] = "FAIL"
    blocked(req, "FINAL_EVIDENCE_INVALID:MANIFEST_OUTCOME_BINDING_MISMATCH"); checks += 1

    req = base_request(("PASS", "PASS"))
    req["plan_authority_receipt"]["plan_digest"] = "f" * 64
    blocked(req, "PLAN_AUTHORITY_PLAN_DIGEST"); checks += 1

    for forbidden_key in ("evidence_ledger", "receipts", "control_execution_request"):
        req = base_request(("PASS", "PASS"))
        req[forbidden_key] = {}
        blocked(req, "EVIDENCE_COLLECTION_OR_CONTROL_EXECUTION_FORBIDDEN")
        checks += 1

    source = inspect.getsource(closure_source)
    assert "private.lf_evidence_ledger" not in source
    assert "EVIDENCE_COLLECTION_OR_CONTROL_EXECUTION_FORBIDDEN" in source
    checks += 2

    req = base_request(("PASS", "PASS"))
    one = build_closure_verdict(req)
    two = build_closure_verdict(copy.deepcopy(req))
    assert one["verdict_sha256"] == two["verdict_sha256"]
    assert "raw_evidence" not in str(one)
    checks += 2

    print(f"PASS_POST_PASE_CLOSURE_GATE_V1 checks={checks}")


if __name__ == "__main__":
    main()
