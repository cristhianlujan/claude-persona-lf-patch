#!/usr/bin/env python3
from __future__ import annotations

import copy

from plan_authority_drift_guard_v1 import (
    authority_proof_digest,
    canonical_sha256,
    delta_digest,
    evaluate_plan_authority,
    sha256_text,
)

ANCHOR_PLAN = "9b234da6cdec56c141cc452e3997650c93cdf3a27f64d9b5858bea311476c648"
PLAN_ID = "LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1"
WS = '{"name": "Super Admin — Transversal Capabilities + POST-PASE", "status": "ACTIVE"}'
ITEMS = '[{"status": "DONE", "work_code": "SADM-PP-L0-001"}]'
DEPS = '[{"depends_on": "SADM-PP-L0-001", "relation_type": "REQUIRES", "work_code": "SADM-PP-L0-006"}]'


def anchor(*, event_id=19435, plan_id=PLAN_ID, digest=ANCHOR_PLAN, ws=WS, items=ITEMS, deps=DEPS):
    return {
        "anchor_event_id": event_id,
        "plan_id": plan_id,
        "legacy_plan_digest": digest,
        "workstream_sha256": sha256_text(ws),
        "work_items_sha256": sha256_text(items),
        "dependencies_sha256": sha256_text(deps),
    }


def request(plan_digest=ANCHOR_PLAN, *, authority_digests=None):
    return {
        "orchestrator_execution_id": "ORCH-1",
        "consumer_execution_id": "CONSUMER-1",
        "capability_code": "PLAN_AUTHORITY_DRIFT_GUARD",
        "plan_digest": plan_digest,
        "dispatch_receipt_id": "DISPATCH-1",
        "request_digest": "a" * 64,
        "entry_guard_readback": {"decision": "ORCHESTRATOR_ENTRY_ACCEPTED"},
        "authority_refs": {
            "plan_delta_authority_receipt_digests": list(authority_digests or [])
        },
    }


def currentness(decision="CURRENT", ready=True):
    base = {
        "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
        "authority_layer": "CURRENTNESS_AUTHORITY",
        "decision": decision,
        "ready": ready,
    }
    base["receipt_sha256"] = canonical_sha256(base)
    return base


def live(*, plan_id=PLAN_ID, ws=WS, items=ITEMS, deps=DEPS):
    return {
        "plan_id": plan_id,
        "workstream_canonical_text": ws,
        "work_items_canonical_text": items,
        "dependencies_canonical_text": deps,
    }


def make_proof(event_id, plan_id, previous, nxt, *, decision="AUTHORIZED_PLAN_DELTA"):
    proof = {
        "schema_version": "LF_PLAN_DELTA_AUTHORITY_READBACK_V1",
        "authority": "PLAN_AUTHORITY",
        "decision": decision,
        "event_id": event_id,
        "plan_id": plan_id,
        "previous_plan_digest": previous,
        "next_plan_digest": nxt,
    }
    proof["receipt_digest"] = authority_proof_digest(proof)
    return proof


def make_delta(previous, nxt, *, event_id=19591, plan_id=PLAN_ID, ws=WS, items=ITEMS, deps=DEPS, decision="AUTHORIZED_PLAN_DELTA"):
    proof = make_proof(event_id, plan_id, previous, nxt, decision=decision)
    d = {
        "delta_event_id": event_id,
        "plan_id": plan_id,
        "previous_plan_digest": previous,
        "next_plan_digest": nxt,
        "workstream_sha256": sha256_text(ws),
        "work_items_sha256": sha256_text(items),
        "dependencies_sha256": sha256_text(deps),
        "authorization_proof": proof,
    }
    d["delta_digest"] = delta_digest(d)
    return d


def main() -> int:
    checks = 0

    r = evaluate_plan_authority(request=request(), anchor=anchor(), live_snapshot=live(), currentness_receipt=currentness(), authorized_deltas=[])
    assert r["decision"] == "MATCH" and r["ready"] is True
    checks += 1

    bad = request(); bad["entry_guard_readback"] = {"decision": "BLOCK"}
    r = evaluate_plan_authority(request=bad, anchor=anchor(), live_snapshot=live(), currentness_receipt=currentness(), authorized_deltas=[])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "ORCHESTRATOR_ENTRY_REQUIRED"
    checks += 1

    r = evaluate_plan_authority(request=request(), anchor=anchor(), live_snapshot=live(), currentness_receipt=currentness("STALE_AFFECTED", False), authorized_deltas=[])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "CURRENTNESS_NOT_READY"
    checks += 1

    changed_items = '[{"status": "DONE", "work_code": "SADM-PP-L0-001"}, {"status": "DONE", "work_code": "SADM-PP-L1-010"}]'
    r = evaluate_plan_authority(request=request(), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness(), authorized_deltas=[])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "LIVE_COMPONENT_DRIFT_WITHOUT_DELTA"
    checks += 1

    next_digest = "b" * 64
    d = make_delta(ANCHOR_PLAN, next_digest, items=changed_items)
    auth_digest = d["authorization_proof"]["receipt_digest"]
    r = evaluate_plan_authority(request=request(next_digest, authority_digests=[auth_digest]), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness("CURRENT_REBOUND"), authorized_deltas=[d])
    assert r["decision"] == "AUTHORIZED_DELTA" and r["ready"] is True
    assert r["authorized_delta_event_ids"] == [19591]
    checks += 2

    r = evaluate_plan_authority(request=request(next_digest), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness(), authorized_deltas=[d])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "DELTA_AUTHORIZATION_NOT_CROSSBOUND_TO_REQUEST"
    checks += 1

    broken = copy.deepcopy(d); broken["previous_plan_digest"] = "c" * 64
    broken["authorization_proof"] = make_proof(19591, PLAN_ID, "c" * 64, next_digest)
    broken["delta_digest"] = delta_digest(broken)
    bd = broken["authorization_proof"]["receipt_digest"]
    r = evaluate_plan_authority(request=request(next_digest, authority_digests=[bd]), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness(), authorized_deltas=[broken])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "DELTA_CHAIN_PREVIOUS_MISMATCH"
    checks += 1

    tampered = copy.deepcopy(d); tampered["work_items_sha256"] = "d" * 64
    r = evaluate_plan_authority(request=request(next_digest, authority_digests=[auth_digest]), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness(), authorized_deltas=[tampered])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "DELTA_DIGEST_MISMATCH"
    checks += 1

    forged = make_delta(ANCHOR_PLAN, next_digest, items=changed_items, decision="OBSERVED_ONLY")
    fd = forged["authorization_proof"]["receipt_digest"]
    r = evaluate_plan_authority(request=request(next_digest, authority_digests=[fd]), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness(), authorized_deltas=[forged])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "DELTA_AUTHORIZATION_DECISION_MISMATCH"
    checks += 1

    d2_digest = "e" * 64
    d1 = make_delta(ANCHOR_PLAN, next_digest, event_id=19591, items=changed_items)
    changed_deps = DEPS[:-1] + ', {"depends_on": "SADM-PP-L1-010", "relation_type": "REQUIRES", "work_code": "SADM-PP-L2-011"}]'
    d2 = make_delta(next_digest, d2_digest, event_id=19592, items=changed_items, deps=changed_deps)
    refs = [d1["authorization_proof"]["receipt_digest"], d2["authorization_proof"]["receipt_digest"]]
    r = evaluate_plan_authority(request=request(d2_digest, authority_digests=refs), anchor=anchor(), live_snapshot=live(items=changed_items, deps=changed_deps), currentness_receipt=currentness(), authorized_deltas=[d1, d2])
    assert r["decision"] == "AUTHORIZED_DELTA" and r["authorized_delta_event_ids"] == [19591, 19592]
    checks += 1

    r = evaluate_plan_authority(request=request("f" * 64, authority_digests=[auth_digest]), anchor=anchor(), live_snapshot=live(items=changed_items), currentness_receipt=currentness(), authorized_deltas=[d])
    assert r["decision"] == "UNREGISTERED_DRIFT" and r["reason"] == "REQUEST_PLAN_DIGEST_NOT_DELTA_TIP"
    checks += 1

    alt_plan = "ALT_PLAN"
    alt_digest = "1" * 64
    alt_ws = '{"name": "Other plan", "status": "ACTIVE"}'
    alt_items = '[{"status": "READY", "work_code": "ALT-1"}]'
    alt_deps = '[]'
    a = anchor(event_id=100, plan_id=alt_plan, digest=alt_digest, ws=alt_ws, items=alt_items, deps=alt_deps)
    rq = request(alt_digest)
    r = evaluate_plan_authority(request=rq, anchor=a, live_snapshot=live(plan_id=alt_plan, ws=alt_ws, items=alt_items, deps=alt_deps), currentness_receipt=currentness(), authorized_deltas=[])
    assert r["decision"] == "MATCH" and r["anchor_event_id"] == 100 and r["plan_id"] == alt_plan
    checks += 1

    print(f"PASS_PLAN_AUTHORITY_DRIFT_GUARD_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
