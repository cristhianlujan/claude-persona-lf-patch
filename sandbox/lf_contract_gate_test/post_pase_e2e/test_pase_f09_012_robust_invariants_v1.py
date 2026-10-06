#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE / "PASE_F09_012_robust_invariants_qualification_v1.json"

def main() -> int:
    d = json.loads(PROOF.read_text(encoding="utf-8"))
    checks = 0
    def ok(cond, name):
        nonlocal checks
        checks += 1
        if not cond:
            raise AssertionError(name)

    ok(d["schema_version"] == "PASE_F09_012_ROBUST_INVARIANTS_QUALIFICATION_V1", "schema")
    ok(d["work_code"] == "PASE-ATOM-F09-012", "work")
    ok(len(d["source_exact_main_sha"]) == 40, "exact head")
    ok(d["source_authority"] == {
        "source_pack_event_id": 19827,
        "pattern_event_id": 19806,
        "r17_event_id": 19786,
        "predecessor_terminal_event_id": 20380,
    }, "source authority")
    ok(all(len(v) == 40 for v in d["current_source_blobs"].values()), "current blobs")

    c = d["representative_coverage"]
    for name in ("nominal","negative","boundary","partial_failure","retry_idempotency",
                 "stale_evidence","concurrency","equivalent_replay"):
        ok(c[name]["verdict"] == "PASS", f"coverage:{name}")
    ok(c["nominal"]["positive_terminal_scenarios"] == 5, "nominal count")
    ok(c["partial_failure"]["failed_receipt_persisted"] is False, "partial failed receipt")
    ok(c["partial_failure"]["downstream_closure_executed"] is False, "partial closure")
    ok(c["retry_idempotency"]["first_decision"] == "ANCHORED", "retry first")
    ok(c["retry_idempotency"]["retry_decision"] == "IDEMPOTENT_REPLAY", "retry replay")
    ok(c["retry_idempotency"]["same_receipt_id"] is True, "retry receipt id")
    ok(c["retry_idempotency"]["same_receipt_sha256"] is True, "retry receipt sha")
    ok(c["retry_idempotency"]["post_rollback_residue_count"] == 0, "rollback residue")
    ok(c["stale_evidence"]["dispatch_count_after_stale"] == 0, "stale no dispatch")
    ok(c["stale_evidence"]["terminal_control_count_after_stale"] == 0, "stale no terminal")
    ok(c["concurrency"]["proof_mode"] == "DATABASE_ATOMIC_UNIQUE_GUARD_PLUS_IDEMPOTENT_ANCHOR", "concurrency authority")
    ok(c["concurrency"]["physical_parallel_sessions_executed"] is False, "no invented parallel run")
    ok(c["equivalent_replay"]["retry_same_receipt_identity"] is True, "equivalent replay")
    ok(c["equivalent_replay"]["completed_no_effect_proofs"] >= 1, "equivalence proof")

    inv = d["invariants"]
    ok(inv["no_bypass"] is True, "no bypass")
    ok(inv["no_stale_pass"] is True, "no stale pass")
    ok(inv["duplicate_execution_count"] == 0, "duplicates")
    ok(inv["unplanned_control_count"] == 0, "unplanned")
    for name in (
        "blocking_failure_cannot_close_pass",
        "semantic_to_transport_parity_at_receiver",
        "exactly_one_current_authorized_runner_per_applicable_control",
        "zero_multiple_stale_binding_fails_closed",
        "observe_only_cannot_block_merge",
        "dispatch_success_alone_cannot_close_control_pass",
        "retry_replay_one_material_effect",
        "retry_replay_one_terminal_lineage",
    ):
        ok(inv[name] is True, name)

    s = d["safety"]
    ok(s["qualification_only"] is True, "qualification only")
    for name in ("live_domain_controls_executed","runtime_or_deploy_touched",
                 "production_touched","pase_workflow_activated","zip_used_as_authority"):
        ok(s[name] is False, f"safety:{name}")
    ok(s["rollback_residue_count"] == 0, "safety residue")
    ok(d["terminal"]["verdict"] == "PASS", "terminal")
    ok(d["terminal"]["blocking_finding_count"] == 0, "blockers")
    ok(d["terminal"]["activation_authorized"] is False, "activation")
    ok(d["terminal"]["production_authorized"] is False, "production")
    print(f"PASS_PASE_F09_012_ROBUST_INVARIANTS_V1 checks={checks}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
