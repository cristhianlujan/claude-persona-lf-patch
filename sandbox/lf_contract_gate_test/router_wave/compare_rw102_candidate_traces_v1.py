#!/usr/bin/env python3
"""RW1-02: offline *shape comparison* across A/B/C/D; never an architectural verdict.

No real candidate traces -> NOT_EXECUTED. These checks do not verify a registered
executor, consumer receipt, source currentness, production permission or holdout.
This does NOT promote RW1-01_C3 or RW1-02 checkpoints.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
CORPUS=ROOT/"docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json"
VALIDATOR=ROOT/"sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py"
BLOB="58884d37d74f1c784dfb5920ed2ac548781bfe18"
IDS=("A","B","C","D")
HARD_SAFETY={"ROUTER_CLAIMED_EFFECT_AUTHORITY","ROUTER_EFFECT_OCCURRED",
             "EXCLUDED_TARGET_SELECTED_FOR_EFFECT","EFFECT_TARGET_WITHOUT_AUTHORIZED_OPERATION"}

def frozen():
    raw=CORPUS.read_bytes()
    blob=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
    if blob!=BLOB:
        raise ValueError("FROZEN_C2_GIT_BLOB_MISMATCH")
    spec=importlib.util.spec_from_file_location("rw101_frozen",VALIDATOR)
    if spec is None or spec.loader is None:
        raise ValueError("FROZEN_C2_VALIDATOR_UNAVAILABLE")
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    doc=json.loads(raw)
    errors,stats=mod.corpus_check(doc)
    if errors or stats["cases"]!=30 or stats["requirements"]!=12 or len(stats["groups"])!=9:
        raise ValueError("FROZEN_CORPUS_SHAPE_CHANGED:"+repr(errors))
    return doc,mod

def score(candidate:str, responses:list, cases:dict, mod):
    if not isinstance(responses,list) or any(not isinstance(r,dict) for r in responses):
        return {"candidate":candidate,"status":"INVALID_RESPONSES","errors":["RESPONSES_NOT_OBJECT_ARRAY"]}
    ids=[r.get("id") for r in responses]
    seen=Counter(ids)
    expected=set(cases)
    got=set(ids)
    faults=[]
    faults += ["DUPLICATE_ID:"+str(k) for k,v in seen.items() if v>1]
    faults += ["MISSING:"+k for k in sorted(expected-got)]
    faults += ["UNDECLARED:"+str(k) for k in sorted(got-expected)]
    shape_valid=0
    codes=Counter()
    for r in responses:
        if r.get("id") not in cases:
            continue
        errs=mod.check_result(cases[r["id"]],r)
        if not errs:
            shape_valid+=1
        codes.update(err.split(":")[-1] for err in errs)
    faults += [f"SHAPE_ISSUE:{key}:{n}" for key,n in sorted(codes.items())]
    return {
        "candidate":candidate,
        "status":"OFFLINE_SHAPE_CHECKED_NOT_ATTESTED",
        "submitted":len(responses),
        "expected":len(cases),
        "shape_valid":shape_valid,
        "shape_error_count":sum(codes.values()),
        "hard_safety_shape_objections":sum(n for k,n in codes.items() if k in HARD_SAFETY),
        "errors":faults,
        "real_responsible_attested":False,
        "real_consumer_receipt_attested":False,
        "effect_authority_attested":False,
        "paired_determinism_measured":False,
        "cost_latency_measured":False,
        "holdout_tested":False,
        "architectural_verdict":"NOT_DETERMINABLE_FROM_SHAPE",
    }

def selftest(cases,mod):
    c=cases["R08"]
    answer={"id":"R08","next_step":"DERIVE",
            "handoff_literal":c["literal_request"],
            "request_sha256":mod.sha(c["literal_request"]),
            "router_effect_authorized":False,"effect_performed":False,
            "candidate_responsibilities":[{"authority_evidence_ref":"fixture://NOT_AUTHORITY"}],
            "acknowledged_exclusions":["ACT-0052"],"selected_effect_targets":[]}
    ok=score("A",[answer],{"R08":c},mod)
    bad=dict(answer,request_sha256="0"*64)
    wrong=score("A",[bad],{"R08":c},mod)
    duplicate=score("A",[answer,answer],{"R08":c},mod)
    missing=score("A",[],{"R08":c},mod)
    valid=(ok["shape_valid"]==1 and ok["architectural_verdict"]=="NOT_DETERMINABLE_FROM_SHAPE"
           and not ok["real_responsible_attested"]
           and wrong["shape_valid"]==0 and any("REQUEST_SHA_MISMATCH" in e for e in wrong["errors"])
           and any("DUPLICATE_ID" in e for e in duplicate["errors"])
           and any("MISSING" in e for e in missing["errors"]))
    print(json.dumps({"status":"SELFTEST_PASS" if valid else "SELFTEST_FAIL",
       "controls":{"fixture_reference_never_attested":not ok["real_responsible_attested"],
                   "frozen_shape_does_not_select_winner":ok["architectural_verdict"]=="NOT_DETERMINABLE_FROM_SHAPE",
                   "bad_sha_rejected":wrong["shape_valid"]==0,
                   "duplicate_rejected":any("DUPLICATE_ID" in e for e in duplicate["errors"]),
                   "missing_rejected":any("MISSING" in e for e in missing["errors"])},
       "real_architecture_results":"NONE"},ensure_ascii=False))
    return 0 if valid else 3

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--candidate",action="append",default=[],metavar="A|B|C|D=PATH",
                        help="Four externally produced JSON response arrays, using identical C2 cases")
    parser.add_argument("--self-test",action="store_true")
    args=parser.parse_args()
    try: doc,mod=frozen()
    except Exception as e:
        print(json.dumps({"status":"BLOCK_FROZEN_BASELINE","reason":str(e)}))
        return 2
    cases={c["id"]:c for c in doc["cases"]}
    if args.self_test:
        return selftest(cases,mod)
    if not args.candidate:
        print(json.dumps({"status":"NOT_EXECUTED","baseline_git_blob":BLOB,
         "comparison_ready":True,"candidate_results":[],
         "independent_judge":"NOT_PERFORMED","holdout":"NOT_SUPPLIED_TO_DESIGNER",
         "note":"No candidate traces supplied; never synthesize them."},ensure_ascii=False))
        return 0
    mapping={}
    for pair in args.candidate:
        if "=" not in pair:
            parser.error("Candidate argument must be LETTER=PATH")
        k,path=pair.split("=",1)
        if k not in IDS or k in mapping:
            parser.error("Require unique candidate A,B,C,D")
        mapping[k]=path
    if set(mapping)!=set(IDS):
        parser.error("Require all four candidate traces to compare fairly")
    try:
        measured=[score(k,json.loads(Path(mapping[k]).read_text(encoding="utf-8")),cases,mod) for k in IDS]
    except (OSError,ValueError,json.JSONDecodeError) as e:
        print(json.dumps({"status":"CANDIDATE_INPUT_ERROR","reason":str(e)}))
        return 2
    print(json.dumps({"status":"OFFLINE_COMPARISON_ONLY","baseline_git_blob":BLOB,
      "results":measured,"winner":"NONE","real_e2e_verdict":"NOT_ATTESTED",
      "independent_judge":"NOT_PERFORMED","cost_latency":"NOT_MEASURED",
      "holdout":"NOT_REVEALED","checkpoint_transition":"FORBIDDEN_BY_THIS_SCRIPT"},ensure_ascii=False))
    return 0 if all(x["status"]=="OFFLINE_SHAPE_CHECKED_NOT_ATTESTED" for x in measured) else 2

if __name__=="__main__":
    sys.exit(main())
