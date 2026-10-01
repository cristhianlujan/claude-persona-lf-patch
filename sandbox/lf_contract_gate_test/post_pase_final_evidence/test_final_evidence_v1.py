from __future__ import annotations

import copy

from final_evidence_v1 import (
    FinalEvidenceBlocked,
    build_final_evidence_manifest,
    controls_digest,
    outcome_binding_digest,
    verify_final_evidence_manifest,
)

PLAN_DIGEST = "a" * 64
MERGE_SHA = "b" * 40


def typed(receipt_id, receipt_sha256, outcome):
    return {
        "schema_version": "LF_TYPED_CONTROL_TERMINAL_RECEIPT_V1",
        "validation_decision": "TYPED_RECEIPT_VALIDATED",
        "receipt_id": receipt_id,
        "receipt_sha256": receipt_sha256,
        "terminal_outcome": outcome,
        "outcome_binding_sha256": outcome_binding_digest(receipt_id, receipt_sha256, outcome),
    }


def base_request(outcome_a="PASS", outcome_b="PASS"):
    controls = [
        {"control_code": "AUTHORITY_READBACK", "disposition": "REQUIRED"},
        {"control_code": "GITHUB_RECONCILIATION", "disposition": "REQUIRED"},
        {"control_code": "RUNTIME_DEPLOY_VERIFICATION", "disposition": "NOT_APPLICABLE"},
    ]
    r1_id, r1_sha = "11111111-1111-1111-1111-111111111111", "1" * 64
    r2_id, r2_sha = "22222222-2222-2222-2222-222222222222", "3" * 64
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
        "receipts": [
            {
                "control_code": "AUTHORITY_READBACK",
                "receipt_id": r1_id,
                "receipt_sha256": r1_sha,
                "execution_id": "CTRL-EXEC-001",
                "capability_code": "AUTHORITY_READBACK",
                "gate_code": "AUTHORITY_READBACK",
                "source_head_sha": MERGE_SHA,
                "subject_ref": "github://repo@" + MERGE_SHA + "/authority",
                "subject_sha256": "2" * 64,
                "authority_ref": "supabase://authority/readback",
                "resolver_id": "LF_SUPABASE_READBACK_V1",
                "verification_state": "VERIFIED",
                "plan_digest": PLAN_DIGEST,
                "typed_receipt": typed(r1_id, r1_sha, outcome_a),
            },
            {
                "control_code": "GITHUB_RECONCILIATION",
                "receipt_id": r2_id,
                "receipt_sha256": r2_sha,
                "execution_id": "CTRL-EXEC-002",
                "capability_code": "GITHUB_RECONCILIATION",
                "gate_code": "GITHUB_RECONCILIATION",
                "source_head_sha": MERGE_SHA,
                "subject_ref": "github://repo@" + MERGE_SHA + "/reconcile",
                "subject_sha256": "4" * 64,
                "authority_ref": "github://main@" + MERGE_SHA,
                "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
                "verification_state": "VERIFIED",
                "plan_digest": PLAN_DIGEST,
                "typed_receipt": typed(r2_id, r2_sha, outcome_b),
            },
        ],
    }


def blocked(mutator, expected):
    req = base_request()
    mutator(req)
    try:
        build_final_evidence_manifest(req)
    except FinalEvidenceBlocked as exc:
        assert str(exc) == expected, (str(exc), expected)
        return
    raise AssertionError(f"expected block {expected}")


def main():
    checks = 0

    for outcome in ("PASS", "FAIL", "BLOCKED"):
        req = base_request(outcome, "PASS")
        out = build_final_evidence_manifest(req)
        assert out["receipt_refs"][0]["terminal_outcome"] == outcome
        assert verify_final_evidence_manifest(out)
        checks += 2

    out = build_final_evidence_manifest(base_request("FAIL", "BLOCKED"))
    assert out["decision"] == "FINAL_EVIDENCE_MANIFEST_READY"
    assert out["receipt_count"] == 2
    assert out["required_controls"] == ["AUTHORITY_READBACK", "GITHUB_RECONCILIATION"]
    assert out["not_applicable_controls"] == ["RUNTIME_DEPLOY_VERIFICATION"]
    assert out["raw_evidence_embedded"] is False
    assert "manifest_sha256" in out and len(out["manifest_sha256"]) == 64
    assert "verification_payload" not in str(out)
    assert "closure_verdict" not in out
    checks += 8

    blocked(lambda r: r.update(orchestrator_entry={}), "ORCHESTRATOR_ENTRY_REQUIRED"); checks += 1
    blocked(lambda r: r["plan_authority_receipt"].update(plan_digest="c" * 64), "PLAN_AUTHORITY_PLAN_DIGEST"); checks += 1
    blocked(lambda r: r["plan_authority_receipt"].update(controls_digest="d" * 64), "PLAN_AUTHORITY_CONTROLS_DIGEST"); checks += 1
    blocked(lambda r: r["receipts"].pop(), "REQUIRED_RECEIPT_SET_MISMATCH"); checks += 1
    blocked(lambda r: r["receipts"].append(copy.deepcopy(r["receipts"][0])), "DUPLICATE_CONTROL_RECEIPT"); checks += 1
    blocked(lambda r: r["receipts"][0].update(source_head_sha="c" * 40), "RECEIPT_SOURCE_HEAD_MISMATCH"); checks += 1
    blocked(lambda r: r["receipts"][0].update(plan_digest="c" * 64), "RECEIPT_PLAN_DIGEST_MISMATCH"); checks += 1
    blocked(lambda r: r["receipts"][0].update(verification_state="ANCHORED"), "RECEIPT_NOT_VERIFIED"); checks += 1
    blocked(lambda r: r["controls"].append({"control_code":"AUTHORITY_READBACK","disposition":"REQUIRED"}), "DUPLICATE_CONTROL"); checks += 1
    blocked(lambda r: r["receipts"].append({**copy.deepcopy(r["receipts"][0]), "control_code":"RUNTIME_DEPLOY_VERIFICATION", "receipt_id":"33333333-3333-3333-3333-333333333333"}), "EXTRA_OR_NA_RECEIPT"); checks += 1

    blocked(lambda r: r["receipts"][0]["typed_receipt"].pop("terminal_outcome"), "TERMINAL_OUTCOME_REQUIRED"); checks += 1
    blocked(lambda r: r["receipts"][0]["typed_receipt"].update(terminal_outcome="WAIVED"), "TERMINAL_OUTCOME_INVALID"); checks += 1
    blocked(lambda r: r["receipts"][0]["typed_receipt"].update(terminal_outcome="FAIL"), "TERMINAL_OUTCOME_BINDING_MISMATCH"); checks += 1

    tampered = build_final_evidence_manifest(base_request())
    tampered["receipt_refs"][0]["terminal_outcome"] = "FAIL"
    try:
        verify_final_evidence_manifest(tampered)
    except FinalEvidenceBlocked as exc:
        assert str(exc) in {"MANIFEST_OUTCOME_BINDING_MISMATCH", "MANIFEST_DIGEST_MISMATCH"}
    else:
        raise AssertionError("expected manifest tamper block")
    checks += 1

    no_raw = build_final_evidence_manifest(base_request())
    assert set(no_raw["receipt_refs"][0]) == {
        "control_code", "receipt_id", "receipt_sha256", "terminal_outcome", "outcome_binding_sha256"
    }
    checks += 1

    print(f"PASS_POST_PASE_FINAL_EVIDENCE_OUTCOME_DELTA_V1 checks={checks}")


if __name__ == "__main__":
    main()
