#!/usr/bin/env python3
import argparse, hashlib, json, subprocess, sys
from pathlib import Path

CODES=[
 "DESIGN_CODE_ALIGNMENT",
 "SECURITY_AUTHORITY_INVARIANTS",
 "CURRENT_SOURCE_AND_ACL",
 "ROLLBACK_LEGACY_COMPATIBILITY",
 "NO_REGRESSION_SCOPE",
]

def git_blob(path: Path)->str:
    return subprocess.check_output(["git","hash-object",str(path)], text=True).strip()

def norm_sha(obj)->str:
    raw=json.dumps(obj,ensure_ascii=False,separators=(",",":")).encode()
    return hashlib.sha256(raw).hexdigest()

def validate(packet_path: Path,capture_path: Path):
    packet=json.loads(packet_path.read_text(encoding="utf-8"))
    cap=json.loads(capture_path.read_text(encoding="utf-8"))
    assert cap["schema_version"]=="RW104_C3_GPT_NATIVE_CAPTURE_V1"
    assert cap["subject_ref"]=="LF_ROUTER_ARCHITECTURE_WAVE_V1/RW1-04/RW1-04_C3"
    assert git_blob(packet_path)==cap["packet_git_blob"]=="7a5c0e9048ebd3029efe258ade9a352ddaacc7ee"
    assert cap["evidence_tier"]=="OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT"
    assert cap["separate_chat_required"] is True
    assert cap["separate_chat_reference_verified"] is False
    assert cap["isolation_provable"] is False
    assert cap["owner_provided_capture"] is True
    for k in ["provider_attested","real_execution_receipt","independent_review","runtime_activation","production_activation"]:
        assert cap[k] is False
    out=cap["raw_output"]
    assert norm_sha(out)==cap["normalized_output_sha256"]=="cc6682cafa121634e797b9465bff38c8f35c3f89a21ad13e0c774daeea1a3fd5"
    assert out["schema_version"]=="RW104_C3_GPT_NATIVE_BLIND_REVIEW_V1"
    assert out["unit"]=="RW1-04"
    items={x["item_id"]:x for x in out["items"]}
    assert set(items)=={"ITEM_A","ITEM_B"}
    packet_items={x["item_id"]:x for x in packet["items"]}
    assert set(packet_items)=={"ITEM_A","ITEM_B"}
    for item_id, expected_result, verdict in [("ITEM_A","PASS","PASS"),("ITEM_B","FAIL","FAIL")]:
        item=items[item_id]
        assert item["verdict"]==verdict
        assert [c["code"] for c in item["checks"]]==CODES
        assert all(c["result"]==expected_result for c in item["checks"])
        text=packet_items[item_id]["text"]
        for c in item["checks"]:
            refs=c["evidence_refs"]
            assert 1<=len(refs)<=3
            for ref in refs:
                assert isinstance(ref,str) and len(ref)>=8
                assert ref in text, (item_id,c["code"],ref)
    return {
      "status":"RW104_C3_CAPTURE_PASS",
      "packet_git_blob":cap["packet_git_blob"],
      "normalized_output_sha256":cap["normalized_output_sha256"],
      "real_item_pass":True,
      "decoy_item_fail":True,
      "real_checks_passed":5,
      "decoy_checks_failed":5,
      "separate_chat_reference_verified":False,
      "isolation_provable":False,
      "provider_attested":False,
      "independent_review":False
    }

def self_test(packet_path: Path,capture_path: Path):
    cap=json.loads(capture_path.read_text(encoding="utf-8"))
    cap["raw_output"]["items"][1]["checks"][0]["result"]="PASS"
    tmp=capture_path.parent/".rw104_c3_bad_capture.json"
    tmp.write_text(json.dumps(cap,ensure_ascii=False),encoding="utf-8")
    try:
        try:
            validate(packet_path,tmp)
        except AssertionError:
            return {"status":"RW104_C3_NEGATIVE_SELFTEST_PASS"}
        raise AssertionError("mutated decoy incorrectly passed")
    finally:
        tmp.unlink(missing_ok=True)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("packet")
    ap.add_argument("capture")
    ap.add_argument("--self-test",action="store_true")
    a=ap.parse_args()
    p=Path(a.packet); c=Path(a.capture)
    result=self_test(p,c) if a.self_test else validate(p,c)
    print(json.dumps(result,sort_keys=True))

if __name__=="__main__":
    main()
