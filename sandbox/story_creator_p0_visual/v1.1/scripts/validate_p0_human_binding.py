#!/usr/bin/env python3
"""Fail-closed temporal/binding checks for P0 human review.

New challenges require machine-quality PASS + J00-bound hashes. Historical
legacy challenges remain readback-verifiable only through an explicit legacy
mode and are never considered HUMAN_REVIEW_READY.
"""
from __future__ import annotations
import argparse, copy, json, re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HUMAN_ACTIONS={"CONFIRM_OBSERVATION","CORRECT_WITH_ADJUDICATION","REQUEST_NEW_CAPTURE","REQUEST_ADDITIONAL_CONTEXT","REJECT_AND_BLOCK","ESCALATE_SECURITY","ESCALATE_PRIVACY"}
REVIEWER_ROLES={"P0_VISUAL_ADJUDICATOR","P0_SECURITY_REVIEWER","P0_PRIVACY_REVIEWER"}
SHA256_RE=re.compile(r"^[0-9a-f]{64}$"); SHA1_RE=re.compile(r"^[0-9a-f]{40}$")

def parse_time(value:Any)->datetime|None:
    if not isinstance(value,str): return None
    try: parsed=datetime.fromisoformat(value.replace("Z","+00:00"))
    except ValueError: return None
    if parsed.tzinfo is None: return None
    return parsed.astimezone(timezone.utc)

def validate_binding(challenge:Any,candidate:Any,*,now:datetime,allow_legacy_historical:bool=False)->dict[str,Any]:
    if not isinstance(challenge,dict) or not isinstance(candidate,dict):
        return {"result":"BLOCKED","blocking_assertions":["binding_objects_invalid"],"human_authenticity_claimed":False,"human_review_ready":False,"p0_4_closed":False}
    issued=parse_time(challenge.get("issued_at")); expires=parse_time(challenge.get("expires_at")); comment_time=parse_time(candidate.get("comment_created_at"))
    actions=challenge.get("reviewer_actions") if isinstance(challenge.get("reviewer_actions"),list) else []
    checks={
      "challenge_id_missing":0 if isinstance(challenge.get("challenge_id"),str) and len(challenge["challenge_id"])>=3 else 1,
      "review_id_missing":0 if isinstance(challenge.get("review_id"),str) and len(challenge["review_id"])>=3 else 1,
      "head_sha_invalid":0 if isinstance(challenge.get("head_sha"),str) and SHA1_RE.fullmatch(challenge["head_sha"]) else 1,
      "visual_output_sha_invalid":0 if isinstance(challenge.get("visual_output_sha256"),str) and SHA256_RE.fullmatch(challenge["visual_output_sha256"]) else 1,
      "reviewer_actions_not_exact":0 if set(actions)==HUMAN_ACTIONS and len(actions)==len(HUMAN_ACTIONS) else 1,
      "reviewer_role_invalid":0 if challenge.get("required_reviewer_role") in REVIEWER_ROLES else 1,
      "challenge_time_invalid":0 if issued is not None and expires is not None and issued<expires else 1,
      "challenge_not_yet_valid":0 if issued is not None and issued<=now else 1,
      "challenge_expired":0 if expires is not None and now<expires else 1,
      "comment_time_invalid":0 if comment_time is not None else 1,
      "comment_before_challenge":0 if issued is not None and comment_time is not None and issued<=comment_time else 1,
      "comment_after_expiry":0 if expires is not None and comment_time is not None and comment_time<expires else 1,
      "challenge_id_mismatch":0 if candidate.get("challenge_id")==challenge.get("challenge_id") else 1,
      "review_id_mismatch":0 if candidate.get("review_id")==challenge.get("review_id") else 1,
      "head_sha_mismatch":0 if candidate.get("head_sha")==challenge.get("head_sha") else 1,
      "visual_output_sha_mismatch":0 if candidate.get("visual_output_sha256")==challenge.get("visual_output_sha256") else 1,
      "reviewer_role_mismatch":0 if candidate.get("reviewer_role")==challenge.get("required_reviewer_role") else 1,
      "action_not_governed":0 if candidate.get("action") in HUMAN_ACTIONS and candidate.get("action") in actions else 1,
      "reviewer_identity_missing":0 if isinstance(candidate.get("reviewer_identity"),str) and len(candidate["reviewer_identity"])>=3 else 1,
      "comment_id_missing":0 if isinstance(candidate.get("comment_id"),int) and candidate["comment_id"]>0 else 1,
    }
    quality_fields=("machine_quality_report_sha256","consolidated_visual_reading_sha256")
    legacy=not all(isinstance(challenge.get(k),str) and SHA256_RE.fullmatch(challenge[k]) for k in quality_fields)
    if legacy and not allow_legacy_historical:
        checks["legacy_packet_missing_machine_quality_gate"]=1
    if not legacy:
        checks["machine_quality_not_pass"]=0 if challenge.get("machine_quality_result")=="PASS_VISUAL_QUALITY" else 1
        checks["human_review_ready_not_derived"]=0 if challenge.get("human_review_ready") is True else 1
        checks["j00_execution_missing"]=0 if isinstance(challenge.get("j00_execution_id"),str) and challenge["j00_execution_id"] else 1
        checks["machine_quality_sha_mismatch"]=0 if candidate.get("machine_quality_report_sha256")==challenge.get("machine_quality_report_sha256") else 1
        checks["consolidated_sha_mismatch"]=0 if candidate.get("consolidated_visual_reading_sha256")==challenge.get("consolidated_visual_reading_sha256") else 1
    failed=sorted(k for k,v in checks.items() if v)
    historical_only=legacy and allow_legacy_historical
    result="PASS_LEGACY_HISTORICAL_READBACK" if historical_only and not failed else ("PASS_BINDING_EXTERNAL_AUTH_REQUIRED" if not failed else "BLOCKED")
    return {"result":result,"blocking_assertions":failed,"checks":checks,"reviewer_action_count":len(actions),
            "human_authenticity_claimed":False,"authenticated_external_readback_required":True,
            "human_review_ready":False if historical_only else not failed,"legacy_historical_only":historical_only,"p0_4_closed":False}

def fixture()->tuple[dict[str,Any],dict[str,Any],datetime]:
    ch={"challenge_id":"CH-P0-BINDING-TEST","review_id":"REV-P0-BINDING-TEST","head_sha":"a"*40,"visual_output_sha256":"b"*64,
        "machine_quality_report_sha256":"c"*64,"consolidated_visual_reading_sha256":"d"*64,"machine_quality_result":"PASS_VISUAL_QUALITY",
        "human_review_ready":True,"j00_execution_id":"J00-TEST","reviewer_actions":sorted(HUMAN_ACTIONS),"required_reviewer_role":"P0_VISUAL_ADJUDICATOR",
        "issued_at":"2026-08-09T10:00:00Z","expires_at":"2026-08-09T14:00:00Z"}
    ca={"challenge_id":ch["challenge_id"],"review_id":ch["review_id"],"head_sha":ch["head_sha"],"visual_output_sha256":ch["visual_output_sha256"],
        "machine_quality_report_sha256":ch["machine_quality_report_sha256"],"consolidated_visual_reading_sha256":ch["consolidated_visual_reading_sha256"],
        "reviewer_identity":"synthetic-contract-identity","reviewer_role":ch["required_reviewer_role"],"action":"CONFIRM_OBSERVATION","comment_id":1,
        "comment_created_at":"2026-08-09T11:00:00Z"}
    return ch,ca,datetime(2026,8,9,12,0,tzinfo=timezone.utc)

def self_test()->int:
    ch,ca,now=fixture(); positive=validate_binding(ch,ca,now=now)
    cases=[]
    def add(name,mut,expected):
        c=copy.deepcopy(ch); a=copy.deepcopy(ca); mut(c,a); r=validate_binding(c,a,now=now); cases.append((name,r["result"]=="BLOCKED" and expected in r["blocking_assertions"]))
    add("quality_blocked",lambda c,a:c.update(machine_quality_result="BLOCKED_VISUAL_QUALITY"),"machine_quality_not_pass")
    add("ready_flag_false",lambda c,a:c.update(human_review_ready=False),"human_review_ready_not_derived")
    add("quality_sha_mismatch",lambda c,a:a.update(machine_quality_report_sha256="e"*64),"machine_quality_sha_mismatch")
    add("consolidated_sha_mismatch",lambda c,a:a.update(consolidated_visual_reading_sha256="e"*64),"consolidated_sha_mismatch")
    legacy=copy.deepcopy(ch)
    for k in ("machine_quality_report_sha256","consolidated_visual_reading_sha256","machine_quality_result","human_review_ready","j00_execution_id"): legacy.pop(k,None)
    blocked_legacy=validate_binding(legacy,ca,now=now)
    historical=validate_binding(legacy,ca,now=now,allow_legacy_historical=True)
    ok=(positive["result"]=="PASS_BINDING_EXTERNAL_AUTH_REQUIRED" and positive["human_review_ready"] is True
        and all(v for _,v in cases) and "legacy_packet_missing_machine_quality_gate" in blocked_legacy["blocking_assertions"]
        and historical["result"]=="PASS_LEGACY_HISTORICAL_READBACK" and historical["human_review_ready"] is False)
    print(json.dumps({"schema_version":"p0-human-binding-selftest/v2","result":"PASS_WITH_EVIDENCE" if ok else "BLOCKED",
                      "new_binding_pass":positive["result"],"negative_cases":dict(cases),
                      "legacy_default_blocked":blocked_legacy["result"]=="BLOCKED","legacy_historical_readback_only":historical["result"]},sort_keys=True))
    return 0 if ok else 2

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--challenge",type=Path); ap.add_argument("--candidate",type=Path); ap.add_argument("--now")
    ap.add_argument("--legacy-historical-readback",action="store_true"); ap.add_argument("--self-test",action="store_true")
    args=ap.parse_args()
    if args.self_test:return self_test()
    if args.challenge is None or args.candidate is None or args.now is None: ap.error("--challenge, --candidate and --now required")
    now=parse_time(args.now)
    if now is None: ap.error("--now must be timezone-aware ISO-8601")
    result=validate_binding(json.loads(args.challenge.read_text()),json.loads(args.candidate.read_text()),now=now,allow_legacy_historical=args.legacy_historical_readback)
    print(json.dumps(result,sort_keys=True))
    return 0 if result["result"] in {"PASS_BINDING_EXTERNAL_AUTH_REQUIRED","PASS_LEGACY_HISTORICAL_READBACK"} else 2
if __name__=="__main__": raise SystemExit(main())
