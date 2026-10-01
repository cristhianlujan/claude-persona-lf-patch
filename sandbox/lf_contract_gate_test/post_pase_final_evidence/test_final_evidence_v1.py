from __future__ import annotations

import copy

from final_evidence_v1 import FinalEvidenceBlocked, build_final_evidence_manifest, controls_digest

PLAN_DIGEST = "a" * 64
MERGE_SHA = "b" * 40


def base_request():
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
                "receipt_id": "11111111-1111-1111-1111-111111111111",
                "receipt_sha256": "1" * 64,
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
            },
            {
                "control_code": "GITHUB_RECONCILIATION",
                "receipt_id": "22222222-2222-2222-2222-222222222222",
                "receipt_sha256": "3" * 64,
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
    req = base_request()
    out = build_final_evidence_manifest(req)
    assert out["decision"] == "FINAL_EVIDENCE_MANIFEST_READY"
    assert out["receipt_count"] == 2
    assert out["required_controls"] == ["AUTHORITY_READBACK", "GITHUB_RECONCILIATION"]
    assert out["not_applicable_controls"] == ["RUNTIME_DEPLOY_VERIFICATION"]
    assert out["raw_evidence_embedded"] is False
    assert "manifest_sha256" in out and len(out["manifest_sha256"]) == 64
    assert "verification_payload" not in str(out)
    checks += 7

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

    print(f"PASS_POST_PASE_FINAL_EVIDENCE_V1 checks={checks}")


if __name__ == "__main__":
    main()
