#!/usr/bin/env python3
"""PE10 C3 GPT Native reviewer handoff, untrusted candidate ONLY.
Never invokes a model, asserts provider attestation, records a DB step or admits cutover.
"""
import argparse
import hashlib
import json
from pathlib import Path

SCHEMA = "LF_PE10_C3_GPT_NATIVE_REVIEW_HANDOFF_V1"
SUBJECT = "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10"
REVIEW = "EXEC-PE10C3-INDEP-e983544d2ee0aeb9"
DIMS = ["dependency", "data", "author"]

def digest(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()

def guard(test, reason):
    if not test:
        raise ValueError(reason)

def prepare(source):
    q = source["request"]
    guard(q["subject"]["subject_ref"] == SUBJECT, "SUBJECT_MISMATCH")
    guard(q["review_execution_id"] == REVIEW, "REVIEW_IDENTITY_MISMATCH")
    guard(q["review_next_step"] == "semantic_review" and q["review_result_state"] == "IN_PROGRESS", "REVIEW_NOT_READY")
    guard(q["dispatch_receipt_state"] == "ISSUED_EXACT_ORCHESTRATOR_DISPATCH", "DISPATCH_MISSING")
    guard(q["producer_receipt_state"] == "VERIFIED_PROVIDER_BOUND_SUBJECT", "SOURCE_RECEIPT_MISSING")
    guard(q["source_producer_execution_id"] != REVIEW, "SELF_REVIEW")
    guard(q["subject"]["required_dimensions"] == DIMS, "DIMENSIONS_DRIFT")
    for key in ("subject_sha256", "source_head_sha", "capability_manifest_sha256"):
        val = q.get(key, "")
        guard(len(val) == 64 and all(c in "0123456789abcdef" for c in val), "INVALID_DIGEST:"+key)
    for key in ("subject_receipt_id", "review_dispatch_receipt_id"):
        guard(bool(q.get(key)), "RECEIPT_MISSING:"+key)
    packet = dict(schema=SCHEMA, status="UNATTESTED_REVIEW_REQUEST", provider="GPT_NATIVE",
        review_execution_id=REVIEW, producer_execution_id=q["source_producer_execution_id"],
        subject_ref=SUBJECT, subject_sha256=q["subject_sha256"], source_head_sha=q["source_head_sha"],
        source_receipt_id=q["subject_receipt_id"], dispatch_receipt_id=q["review_dispatch_receipt_id"],
        capability_manifest_sha256=q["capability_manifest_sha256"], required_dimensions=DIMS,
        independent_review_required=True, runtime_provider_attested=False,
        operational_cutover_allowed=False)
    packet["packet_sha256"] = digest(packet)
    return packet

def intake(packet, reply):
    guard(packet.get("schema") == SCHEMA, "PACKET_SCHEMA_INVALID")
    original = packet.get("packet_sha256")
    guard(isinstance(original, str) and digest({k:v for k,v in packet.items() if k != "packet_sha256"}) == original, "PACKET_TAMPERED")
    guard(reply.get("packet_sha256") == original, "RESPONSE_NOT_BOUND")
    guard(reply.get("review_execution_id") == REVIEW and reply.get("subject_sha256") == packet["subject_sha256"], "REVIEW_SUBJECT_MISMATCH")
    guard(reply.get("verdict") in ("PASS", "FAIL"), "VERDICT_INVALID")
    guard(reply.get("reviewer_execution_id") not in ("", None, packet["producer_execution_id"]), "SELF_REVIEW")
    guard(bool(reply.get("rationale_summary")), "RATIONALE_MISSING")
    refs = reply.get("evidence_refs")
    guard(isinstance(refs, list) and len(refs)>0 and all(isinstance(r,str) and r.strip() for r in refs), "EVIDENCE_MISSING")
    guard(reply.get("review_context") == "INDEPENDENT_OPERATION_CONTEXT", "REVIEW_CONTEXT_MISSING")
    guard(reply.get("utility_dimensions_checked") == DIMS, "DIMENSIONS_MISSING")
    measure = reply.get("independence_measure",{})
    guard(measure.get("state") == "INDEPENDENT", "INDEPENDENCE_UNPROVEN")
    for d in DIMS:
        guard(measure.get(d+"_dimension",{}).get("state") == "INDEPENDENT", "INDEPENDENCE_"+d.upper()+"_UNPROVEN")
    # Claimed provider evidence, even if shaped correctly, is NOT authenticated here.
    # Require LF to independently check server/provider receipts before governed RPC.
    return dict(status="CANDIDATE_REQUIRES_SERVER_SIDE_PROVENANCE_VERIFICATION",
        subject_sha256=packet["subject_sha256"], review_execution_id=REVIEW,
        verdict_claim=reply["verdict"], db_write_authorized=False,
        independent_assurance_admitted=False, operational_cutover_allowed=False)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("mode",choices=["prepare","intake"])
    ap.add_argument("--input",type=Path,required=True)
    ap.add_argument("--packet",type=Path)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()
    body=json.loads(args.input.read_text(encoding="utf-8"))
    guard(args.mode != "intake" or args.packet is not None, "PACKET_REQUIRED")
    result=prepare(body) if args.mode=="prepare" else intake(json.loads(args.packet.read_text(encoding="utf-8")),body)
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(result["status"])

if __name__=="__main__":
    main()
