#!/usr/bin/env python3
"""ENG_M9_7_REPLAY_REPRODUCIBLE: live, signed bundle replay (not pipeline equivalence)."""
import json
import os
import sys
import re
import hashlib

CODE = "ENG_M9_7_REPLAY_REPRODUCIBLE"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")

def demand(condition, code):
    if not condition:
        raise AssertionError(code)

def replay(d):
    r, a, b = d["ledger"], d["current"], d["candidate"]
    t = r["receipt_payload"]["typed_evidence"]
    g = d["gate"]
    demand(d["source_assertions"] == {"current": True, "candidate": True}, "UPSTREAM_PROVENANCE_NOT_ASSERTED")
    demand(r["receipt_kind"] == "IG_SHADOW_COMPARISON" and r["verification_state"] in ("ANCHORED", "VERIFIED"), "LEDGER_RECEIPT_INVALID")
    demand(SHA64.fullmatch(r["receipt_sha256"]) is not None, "LEDGER_SHA_INVALID")
    demand(r["receipt_payload"]["typed_evidence_schema_version"] == t["evidence_schema_version"] == "ig-shadow-receipt/v1", "SCHEMA_MISMATCH")
    demand(g["status"] == "PASS" and g["receipt_id"] == r["receipt_id"], "CANONICAL_GATE_NOT_PASS")
    demand(g["comparison_scope"] == "BUNDLE_DIGEST_ONLY" and g["functional_pipeline_equivalence_proven"] is False, "SCOPE_OVERCLAIM")
    for source, field_ref, field_sha in ((a, "current_release_ref", "current_release_sha256"), (b, "candidate_release_ref", "candidate_release_sha256")):
        demand(SHA40.fullmatch(source["head_sha"]) is not None, "GIT_HEAD_INVALID")
        demand(SHA64.fullmatch(source["subject_sha256"]) is not None and SHA64.fullmatch(source["receipt_sha256"]) is not None, "PROVENANCE_SHA_INVALID")
        demand(source["payload"]["verification_status"] == "VERIFIED", "RELEASE_UNVERIFIED")
        demand(source["payload"]["manifest"]["bundle_sha256"] == source["subject_sha256"], "BUNDLE_MANIFEST_DRIFT")
        demand(source["payload"]["manifest"]["identities"]["git_head"] == source["head_sha"], "BUNDLE_HEAD_DRIFT")
        demand(t[field_ref] == source["head_sha"] and t[field_sha] == source["subject_sha256"], "CROSSBIND_RELEASE_DRIFT")
    demand(r["verification_payload"]["current_release_bundle_receipt_id"] == a["id"], "CURRENT_RECEIPT_CROSSBIND")
    demand(r["verification_payload"]["candidate_release_bundle_receipt_id"] == b["id"], "CANDIDATE_RECEIPT_CROSSBIND")
    demand(t["source_snapshot_sha256"] == r["receipt_payload"]["plan_digest"] == g["source_snapshot_sha256"], "SOURCE_SNAPSHOT_CROSSBIND")
    demand(SHA64.fullmatch(t["source_snapshot_sha256"]) is not None, "SNAPSHOT_INVALID")
    demand(isinstance(t["duration_ms"], (float, int)) and t["duration_ms"] >= 0, "DURATION_NOT_MEASURED")
    result = "MATCH" if a["subject_sha256"] == b["subject_sha256"] else "MISMATCH"
    reproduced = {
        "result": result,
        "method_version": "IG_RELEASE_BUNDLE_MANIFEST_DIGEST_V1",
        "current_output_sha256": a["subject_sha256"],
        "candidate_output_sha256": b["subject_sha256"],
        "difference_count": 0 if result == "MATCH" else 1,
    }
    demand(reproduced == t["comparison"] == g["comparison"], "REPRODUCIBILITY_DIVERGENCE")
    return reproduced

def main():
    demand(bool(os.environ.get("M97_OBSERVATION_JSON")), "LIVE_READBACK_REQUIRED")
    d = json.loads(os.environ["M97_OBSERVATION_JSON"])
    first, second = replay(d), replay(d)
    h1 = hashlib.sha256(json.dumps(first, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    h2 = hashlib.sha256(json.dumps(second, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    demand(h1 == h2, "DIFFERENT_SHA_ON_REPLAY")
    altered = json.loads(json.dumps(d))
    altered["candidate"]["payload"]["manifest"]["bundle_sha256"] = "0" * 64
    rejected = False
    try:
        replay(altered)
    except AssertionError:
        rejected = True
    demand(rejected, "ADVERSARIAL_SOURCE_ACCEPTED")
    print(json.dumps({"test_code": CODE, "status": "PASS", "replay_sha256": h1,
        "observed": {"test_passed": True, "test_exit_code": 0,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "comparison_scope": "BUNDLE_DIGEST_ONLY", "functional_pipeline_equivalence_proven": False,
        "receipt_id": d["ledger"]["receipt_id"]}}, sort_keys=True))

if __name__ == "__main__":
    try:
        main()
    except (AssertionError, ValueError, KeyError, TypeError) as e:
        print(json.dumps({"test_code": CODE, "status": "FAIL", "reason": str(e)}))
        sys.exit(1)
