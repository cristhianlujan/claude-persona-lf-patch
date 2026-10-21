#!/usr/bin/env python3
import hashlib, json, sys
from pathlib import Path

CODES=[
 "AUTHORITY_SEPARATION",
 "TRAIN_AND_ROLLBACK_NON_CIRCULAR",
 "STALE_NEGATIVE_FAIL_CLOSED",
 "SYNTHETIC_PROMPTS_BOUNDED",
 "LEGACY_COMPATIBILITY_NO_BYPASS",
]

def load(p): return json.loads(Path(p).read_text(encoding="utf-8"))

def compact_sha(obj):
    raw=json.dumps(obj,ensure_ascii=False,separators=(",",":")).encode()
    return hashlib.sha256(raw).hexdigest()

def fail(msg):
    print(json.dumps({"status":"FAIL","error":msg},ensure_ascii=False,sort_keys=True))
    return 1

def main():
    if len(sys.argv)!=3:
        print("usage: validate_rw103_c3_capture_v1.py PACKET CAPTURE",file=sys.stderr); return 2
    packet=load(sys.argv[1]); cap=load(sys.argv[2])

    if cap.get("schema_version")!="RW103_C3_GPT_NATIVE_CAPTURE_V1": return fail("CAPTURE_SCHEMA")
    if cap.get("subject_ref")!="LF_ROUTER_ARCHITECTURE_WAVE_V1/RW1-03/RW1-03_C3": return fail("SUBJECT")
    if cap.get("packet_git_blob")!="4654cdab6de895890aedaa0163321cb977a174ac": return fail("PACKET_BLOB")
    if cap.get("evidence_tier")!="OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT": return fail("TIER")
    for k in ["provider_attested","real_execution_receipt","independent_review","runtime_activation","production_activation"]:
        if cap.get(k) is not False: return fail("LIMIT_"+k)
    if not cap.get("public_share_access_verified") or not cap.get("public_share_contains_handoff_reference"): return fail("SHARE_BINDING")

    raw=cap.get("raw_output")
    if compact_sha(raw)!=cap.get("raw_output_sha256"): return fail("RAW_SHA")
    if set(raw)!= {"schema_version","unit","items"}: return fail("RAW_TOP_KEYS")
    if raw["schema_version"]!="RW103_C3_GPT_NATIVE_BLIND_REVIEW_V1" or raw["unit"]!="RW1-03": return fail("RAW_IDENTITY")
    if [i.get("item_id") for i in raw.get("items",[])]!=["ITEM_A","ITEM_B"]: return fail("ITEM_ORDER")

    packet_texts={i["item_id"]:i["text"] for i in packet["items"]}
    packet_prompts=json.dumps(packet["synthetic_prompts"],ensure_ascii=False)

    for idx,item in enumerate(raw["items"]):
        if set(item)!= {"item_id","checks","verdict","rationale"}: return fail("ITEM_KEYS")
        if [c.get("code") for c in item["checks"]]!=CODES: return fail("CHECK_ORDER")
        expected="PASS" if idx==0 else "FAIL"
        if item["verdict"]!=expected: return fail("VERDICT_"+item["item_id"])
        for c in item["checks"]:
            if set(c)!= {"code","result","evidence_refs","note"}: return fail("CHECK_KEYS")
            if idx==0 and c["result"]!="PASS": return fail("REAL_CHECK_NOT_PASS")
            if idx==1 and c["result"]!="FAIL": return fail("DECOY_CHECK_NOT_FAIL")
            refs=c.get("evidence_refs",[])
            if not (1<=len(refs)<=3): return fail("REF_COUNT")
            for ref in refs:
                if len(ref)<8: return fail("REF_SHORT")
                needle=ref
                if needle not in packet_texts[item["item_id"]] and needle not in packet_prompts:
                    return fail("REF_NOT_IN_PACKET:"+needle)
            if len(c.get("note","").strip())<10: return fail("NOTE_SHORT")

    decoy_fail={c["code"] for c in raw["items"][1]["checks"] if c["result"]=="FAIL"}
    must={"AUTHORITY_SEPARATION","TRAIN_AND_ROLLBACK_NON_CIRCULAR","STALE_NEGATIVE_FAIL_CLOSED","LEGACY_COMPATIBILITY_NO_BYPASS"}
    if not must.issubset(decoy_fail): return fail("DECOY_REQUIRED_FAILURES")

    print(json.dumps({
      "status":"RW103_C3_CAPTURE_PASS",
      "real_item_pass":True,
      "decoy_item_fail":True,
      "real_checks_passed":5,
      "decoy_checks_failed":5,
      "packet_git_blob":cap["packet_git_blob"],
      "raw_output_sha256":cap["raw_output_sha256"],
      "chat_transcript_ref":cap["chat_transcript_ref"],
      "evidence_tier":cap["evidence_tier"],
      "provider_attested":False,
      "real_execution_receipt":False,
      "independent_review":False
    },ensure_ascii=False,sort_keys=True))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
