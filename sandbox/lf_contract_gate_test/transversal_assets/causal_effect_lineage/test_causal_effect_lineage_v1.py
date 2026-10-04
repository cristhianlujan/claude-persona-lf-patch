from __future__ import annotations

import copy

from causal_effect_lineage_v1 import evaluate_lineage


def _id(scope: str, opaque_id: str) -> dict:
    return {"scope": scope, "opaque_id": opaque_id}


def _receipt(receipt_id: str, sha: str, role: str, parent: dict, correlation: dict, **extra) -> dict:
    payload = {
        "schema_version": "LF_EVIDENCE_LEDGER_RECEIPT_V1",
        "causal_role": role,
        "parent_identity": parent,
        "correlation_identity": correlation,
        "currentness": "CURRENT",
        **extra,
    }
    return {
        "receipt_id": receipt_id,
        "receipt_sha256": sha,
        "verification_state": "VERIFIED",
        "receipt_payload": payload,
    }


def _linked(boundary: str, receiver: str) -> dict:
    parent = _id("lf:causal-parent", "p-01")
    correlation = _id("lf:causal-correlation", "c-01")
    producer_sha = "a" * 64
    receiver_sha = "b" * 64
    return {
        "parent_identity": parent,
        "correlation_identity": correlation,
        "provenance": {"producer": "producer-01", "receiver": receiver, "authority_ref": "evidence-ledger", "boundary": boundary},
        "currentness": {"producer": "CURRENT", "receiver": "CURRENT", "correlation": "CURRENT"},
        "producer_receipt": _receipt("receipt-producer-01", producer_sha, "PRODUCER", parent, correlation),
        "receiver_effect_receipt": _receipt(
            "receipt-receiver-01",
            receiver_sha,
            "RECEIVER_EFFECT",
            parent,
            correlation,
            producer_receipt_sha256=producer_sha,
            effect_ref="effect-01",
        ),
        "receiver_readback": {
            "observed": True,
            "currentness": "CURRENT",
            "effect_ref": "effect-01",
            "receiver_receipt_sha256": receiver_sha,
        },
    }


def run() -> None:
    checks = 0

    ig_async = _linked("ASYNC_JOB", "ig-consumer-n17")
    r = evaluate_lineage(ig_async)
    assert r["state"] == "LINKED" and r["causal_edge_digest"] and not r["business_authority"] and not r["execution_permission"]
    checks += 4

    non_ig_async = _linked("ASYNC_EVENT", "post-pase-proof-consumer")
    non_ig_async["parent_identity"] = _id("lf:causal-parent", "p-02")
    non_ig_async["correlation_identity"] = _id("lf:causal-correlation", "c-02")
    non_ig_async["producer_receipt"]["receipt_payload"]["parent_identity"] = non_ig_async["parent_identity"]
    non_ig_async["producer_receipt"]["receipt_payload"]["correlation_identity"] = non_ig_async["correlation_identity"]
    non_ig_async["receiver_effect_receipt"]["receipt_payload"]["parent_identity"] = non_ig_async["parent_identity"]
    non_ig_async["receiver_effect_receipt"]["receipt_payload"]["correlation_identity"] = non_ig_async["correlation_identity"]
    r2 = evaluate_lineage(non_ig_async)
    assert r2["state"] == "LINKED"
    checks += 1

    heuristic = {
        "name": "same-name",
        "object_ref": "same-object",
        "timestamp": "2026-10-04T09:40:00-05:00",
    }
    rh = evaluate_lineage(heuristic)
    assert rh["state"] == "UNLINKED" and "HEURISTIC_ONLY_INSUFFICIENT" in rh["reasons"]
    checks += 2

    no_readback = copy.deepcopy(ig_async)
    no_readback["receiver_readback"]["observed"] = False
    rr = evaluate_lineage(no_readback)
    assert rr["state"] == "UNLINKED" and "RECEIVER_EFFECT_READBACK_NOT_PROVEN" in rr["reasons"]
    checks += 2

    same_object_only = copy.deepcopy(ig_async)
    same_object_only.pop("producer_receipt")
    same_object_only.pop("receiver_effect_receipt")
    same_object_only["object_ref"] = "object-01"
    rs = evaluate_lineage(same_object_only)
    assert rs["state"] == "UNLINKED"
    checks += 1

    conflict = copy.deepcopy(ig_async)
    conflict["receiver_effect_receipt"]["receipt_payload"]["correlation_identity"] = _id("lf:causal-correlation", "c-other")
    rc = evaluate_lineage(conflict)
    assert rc["state"] == "AMBIGUOUS"
    checks += 1

    stale = copy.deepcopy(ig_async)
    stale["currentness"]["receiver"] = "STALE"
    rstale = evaluate_lineage(stale)
    assert rstale["state"] == "UNLINKED" and "CURRENTNESS_NOT_PROVEN" in rstale["reasons"]
    checks += 2

    pii = copy.deepcopy(ig_async)
    pii["email"] = "person@example.com"
    rpii = evaluate_lineage(pii)
    assert rpii["state"] == "UNLINKED" and "PII_NOT_ALLOWED" in rpii["reasons"]
    checks += 2

    missing_crosslink = copy.deepcopy(ig_async)
    missing_crosslink["receiver_effect_receipt"]["receipt_payload"]["producer_receipt_sha256"] = "c" * 64
    rx = evaluate_lineage(missing_crosslink)
    assert rx["state"] == "UNLINKED" and "RECEIVER_DOES_NOT_CROSSLINK_PRODUCER" in rx["reasons"]
    checks += 2

    source = open(__file__.replace("test_causal_effect_lineage_v1.py", "causal_effect_lineage_v1.py"), encoding="utf-8").read().lower()
    for forbidden in ("input_governance", "pantalla", "familia", "m6.0", "n-17", "post_pase_orchestrator"):
        assert forbidden not in source, forbidden
    checks += 6

    assert {evaluate_lineage({})["state"], r["state"], rc["state"]} == {"LINKED", "UNLINKED", "AMBIGUOUS"}
    checks += 1

    print(f"PASS_CAUSAL_EFFECT_LINEAGE_V1 checks={checks} states=3 async_consumers=2 heuristic_negative=PASS receiver_readbacks=2")


if __name__ == "__main__":
    run()
