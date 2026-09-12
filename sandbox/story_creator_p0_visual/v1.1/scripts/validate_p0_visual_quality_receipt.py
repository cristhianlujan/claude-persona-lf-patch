#!/usr/bin/env python3
"""Validate closed-loop receipt integrity, including reversible crop transforms."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any

def canonical_bytes(v:Any)->bytes:return json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
def sha(v:Any)->str:return hashlib.sha256(canonical_bytes(v)).hexdigest()
def contains(outer:dict[str,Any],inner:dict[str,Any])->bool:
    return (inner["x"]>=outer["x"] and inner["y"]>=outer["y"] and inner["x"]+inner["width"]<=outer["x"]+outer["width"] and inner["y"]+inner["height"]<=outer["y"]+outer["height"])
def validate(receipt:dict[str,Any], candidate:dict[str,Any]|None=None, judge:dict[str,Any]|None=None)->dict[str,Any]:
    reasons=[]
    if receipt.get("schema_version")!="p0-visual-quality-loop-receipt/v1": reasons.append("RECEIPT_SCHEMA_INVALID")
    if receipt.get("p0_5_denominator_eligible") is not False: reasons.append("P0_5_SEPARATION_VIOLATED")
    cycles=receipt.get("cycles",[]) if isinstance(receipt.get("cycles"),list) else [];max_cycles=3
    if len(cycles)>max_cycles: reasons.append("REMEDIATION_BUDGET_EXCEEDED")
    for ci,cycle in enumerate(cycles,1):
        if cycle.get("cycle")!=ci: reasons.append("REMEDIATION_CYCLE_SEQUENCE_INVALID")
        if cycle.get("before_candidate_sha256")==cycle.get("after_candidate_sha256") and cycle.get("state_changed") is True: reasons.append("REMEDIATION_STATE_CHANGE_CLAIM_INVALID")
        for action in cycle.get("actions",[]):
            reread=action.get("targeted_reread")
            if not isinstance(reread,dict): continue
            tr=reread.get("transform")
            if not isinstance(tr,dict): reasons.append("REMEDIATION_COORDINATE_TRANSFORM_MISSING"); continue
            src=tr.get("source_region"); exp=tr.get("expanded_source_crop"); scale=tr.get("scale")
            if not isinstance(src,dict) or not isinstance(exp,dict) or not isinstance(scale,(int,float)) or scale<=0: reasons.append("REMEDIATION_COORDINATE_TRANSFORM_INVALID"); continue
            required=("x","y","width","height")
            if not all(k in src and k in exp for k in required) or not contains(exp,src): reasons.append("REMEDIATION_COORDINATE_MAPPING_NOT_REVERSIBLE"); continue
            for sx,sy in ((src["x"],src["y"]),(src["x"]+src["width"],src["y"]+src["height"])):
                cx=(sx-exp["x"])*scale; cy=(sy-exp["y"])*scale; rx=cx/scale+exp["x"]; ry=cy/scale+exp["y"]
                if abs(rx-sx)>1e-9 or abs(ry-sy)>1e-9: reasons.append("REMEDIATION_COORDINATE_ROUNDTRIP_FAILED")
    if candidate is not None and sha(candidate)!=receipt.get("final_candidate_sha256"): reasons.append("FINAL_CANDIDATE_SHA_MISMATCH")
    if judge is not None:
        if judge.get("candidate_sha256")!=receipt.get("final_candidate_sha256"): reasons.append("J00_FINAL_CANDIDATE_SHA_MISMATCH")
        if judge.get("source_sha256")!=receipt.get("source_sha256"): reasons.append("J00_SOURCE_SHA_MISMATCH")
        if judge.get("judgment")!="PASS" and receipt.get("human_review_ready") is True: reasons.append("READY_WITH_BLOCKED_J00")
    return {"result":"PASS_WITH_EVIDENCE" if not reasons else "BLOCKED","blocking_assertions":sorted(set(reasons)),"remediation_cycles":len(cycles)}
def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("--receipt",type=Path,required=True); ap.add_argument("--candidate",type=Path); ap.add_argument("--judge",type=Path)
    a=ap.parse_args(); load=lambda p:json.loads(p.read_text())
    result=validate(load(a.receipt),load(a.candidate) if a.candidate else None,load(a.judge) if a.judge else None)
    print(json.dumps(result,sort_keys=True)); return 0 if result["result"]=="PASS_WITH_EVIDENCE" else 2
if __name__=="__main__":raise SystemExit(main())
