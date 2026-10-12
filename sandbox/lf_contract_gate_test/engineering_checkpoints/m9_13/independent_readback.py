#!/usr/bin/env python3
"""M9.13 independent evidence reconciler. No DB writes / no release actions.

Input: M913_PACKET_JSON containing live raw checkpoint rows and the HANDOFF event
from the governed Supabase read adapter. This script independently recomputes
both manifest hashes. Caller must bind the externally audited runner identity
and DB-read provenance to the checkpoint assertion; local JSON is not a signature.
"""
import hashlib
import json
import os
import socket
import sys

PLAN = "IG_CURATOR_VALIDATOR_REFACTOR_V2"
BUNDLE = "supabase://programacion.engineering_work_checkpoints/M9-peer-manifest"


def digest(lines):
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def verify(packet, runner_identity):
    problems = []
    if packet.get("plan_code") != PLAN:
        problems.append("WRONG_PLAN")
    handoff = packet.get("handoff") or {}
    if handoff.get("evento_tipo") != "HANDOFF_DEEP_CONTEXT" or not handoff.get("id"):
        problems.append("HANDOFF_MISSING")
    producer = handoff.get("created_by_execution_id")
    if not producer or producer == runner_identity:
        problems.append("INDEPENDENCE_NOT_PROVED")
    if packet.get("bundle_evidence_ref") != BUNDLE:
        problems.append("BUNDLE_REFERENCE_MISMATCH")
    peers = packet.get("peers") or []
    handoff_units = handoff.get("units") or []
    peer_map = {p.get("unit_code"): p for p in peers}
    hu_map = {h.get("unit"): h for h in handoff_units}
    if len(peer_map) != 13 or len(peers) != 13 or len(hu_map) != 13 or len(handoff_units) != 13:
        problems.append("PEER_CARDINALITY")
    if set(peer_map) != set(hu_map) or "M9.13" in peer_map:
        problems.append("PEER_SET_MISMATCH")
    ledger_lines, handoff_lines = [], []
    unit_hashes = {}
    missing_refs = 0
    for unit in sorted(set(peer_map) | set(hu_map)):
        p = peer_map.get(unit) or {}
        h = hu_map.get(unit) or {}
        if p.get("status") != "DONE" or h.get("status") != "DONE":
            problems.append("NOT_DONE:" + unit)
        if p.get("work_code") != h.get("work_code"):
            problems.append("WORK_CODE_MISMATCH:" + unit)
        cps = sorted(p.get("checkpoints") or [], key=lambda x: x.get("sequence_no", -1))
        refs = h.get("evidence_refs") or []
        if len(cps) != len(refs) or not cps:
            problems.append("CHECKPOINT_COUNT_MISMATCH:" + unit)
        local_ledger, local_handoff = [], []
        for i, c in enumerate(cps):
            ref = c.get("evidence_ref") or ""
            other_ref = refs[i] if i < len(refs) else ""
            status = c.get("status") or ""
            if status not in ("DONE", "NOT_APPLICABLE"):
                problems.append("CHECKPOINT_OPEN:" + unit)
            if not ref or not other_ref:
                missing_refs += 1
            head = unit + "|" + str(c.get("checkpoint_code") or "") + "|" + status + "|"
            local_ledger.append(head + ref)
            local_handoff.append(head + other_ref)
        unit_hashes[unit] = {
            "ledger_sha256": digest(local_ledger),
            "handoff_sha256": digest(local_handoff),
        }
        if unit_hashes[unit]["ledger_sha256"] != unit_hashes[unit]["handoff_sha256"]:
            problems.append("UNIT_MANIFEST_SHA_MISMATCH:" + unit)
        ledger_lines.extend(local_ledger)
        handoff_lines.extend(local_handoff)
    if missing_refs:
        problems.append("MISSING_EVIDENCE")
    if handoff.get("dependency_count") != 13 or handoff.get("dependencies_done") != 13:
        problems.append("HANDOFF_DEPENDENCY_COUNT")
    if handoff.get("all_dependencies_done") is not True:
        problems.append("HANDOFF_NOT_ALL_DONE")
    sha_ledger, sha_handoff = digest(ledger_lines), digest(handoff_lines)
    if sha_ledger != sha_handoff:
        problems.append("MANIFEST_SHA_MISMATCH")
    status = "PASS" if not problems else "FAIL"
    result = {
        "schema_version": "IG_M913_INDEPENDENT_CHECK_V1",
        "status": status,
        "test_passed": status == "PASS",
        "test_exit_code": 0 if status == "PASS" else 1,
        "independent_executor_verified": bool(producer and producer != runner_identity),
        "handoff_evidence_verified": not any(x.startswith(("HANDOFF_", "WORK_CODE_", "CHECKPOINT_COUNT_", "UNIT_MANIFEST_", "PEER_", "NOT_DONE:")) for x in problems),
        "manifest_parity_verified": sha_ledger == sha_handoff and len(peer_map) == 13,
        "discrepancy_count": len(problems),
        "problems": problems,
        "ledger_manifest_sha256": sha_ledger,
        "handoff_manifest_sha256": sha_handoff,
        "unit_hashes": unit_hashes,
        "handoff_event_id": handoff.get("id"),
        "handoff_producer": producer,
        "runner_identity": runner_identity,
        "runner_hostname": socket.gethostname(),
        "bundle_evidence_ref": packet.get("bundle_evidence_ref"),
        "source_query_digest": packet.get("source_query_digest"),
    }
    return result


def self_test():
    peers, hu = [], []
    for i in range(13):
        unit = "M9." + str(i if i < 10 else i + 1)
        peers.append({"unit_code": unit, "work_code": "PAULO-" + str(i), "status": "DONE",
                      "checkpoints": [{"sequence_no": 1, "checkpoint_code": "CP",
                                        "status": "DONE", "evidence_ref": "real:" + unit}]})
        hu.append({"unit": unit, "work_code": "PAULO-" + str(i), "status": "DONE",
                   "evidence_refs": ["real:" + unit]})
    packet = {"plan_code": PLAN, "bundle_evidence_ref": BUNDLE,
              "peers": peers, "handoff": {"id": 1, "evento_tipo": "HANDOFF_DEEP_CONTEXT",
              "created_by_execution_id": "ENGINEERING_CLOSURE_EVENT_V1",
              "dependency_count": 13, "dependencies_done": 13,
              "all_dependencies_done": True, "units": hu}}
    assert verify(packet, "SENTINELX:independent")["status"] == "PASS"
    packet["handoff"]["units"][0]["evidence_refs"] = ["tampered"]
    assert verify(packet, "SENTINELX:independent")["status"] == "FAIL"
    packet["handoff"]["units"][0]["evidence_refs"] = ["real:" + peers[0]["unit_code"]]
    assert verify(packet, "ENGINEERING_CLOSURE_EVENT_V1")["status"] == "FAIL"
    del packet["handoff"]["units"][0]["evidence_refs"]
    assert verify(packet, "SENTINELX:independent")["status"] == "FAIL"
    print(json.dumps({"self_test": "PASS", "positive": 1, "negative": 3}))


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        data = os.getenv("M913_PACKET_JSON")
        actor = os.getenv("M913_AUDITED_RUNNER_ID")
        if not data or not actor:
            sys.exit("M913_MISSING_LIVE_READ_OR_AUDITED_EXECUTOR_ID")
        evidence = verify(json.loads(data), actor)
        print(json.dumps(evidence, sort_keys=True))
        sys.exit(evidence["test_exit_code"])
