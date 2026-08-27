#!/usr/bin/env python3
import argparse, hashlib, json, re, sys
from pathlib import Path

SHA = re.compile(r"^[0-9a-f]{64}$")
PASS_UPSTREAM = {"PASS", "PASS_WITH_RESTRICTIONS", "PASS_EVIDENCE_LINEAGE"}

def good_sha(v): return isinstance(v,str) and bool(SHA.fullmatch(v.lower()))
def text(v): return isinstance(v,str) and bool(v.strip())

def evaluate(case):
    if not isinstance(case,dict):
        return {"status":"BLOCK_PIPELINE","blocking_codes":["MALFORMED_CASE"],"readback_codes":[],"gate_states":{"STRUCTURALLY_VALID":False,"PROVENANCE_VALID":False,"SEMANTICALLY_VALID":False,"ARTIFACT_VERIFIED":False,"UPSTREAM_VALID":False}}
    b=[]; r=[]; refs=set(); receipts=set(); authority_declared=False
    candidate_sha=case.get("candidate_sha")
    provenance_required=case.get("provenance_required",True)
    artifact_required=case.get("artifact_required",True)
    if not text(case.get("claim")): b.append("CLAIM_MISSING")
    if not good_sha(candidate_sha): b.append("CANDIDATE_SHA_INVALID")
    sources=case.get("sources")
    if not isinstance(sources,list) or not sources:
        b.append("SOURCE_UNIVERSE_MISSING"); sources=[]
    for i,s in enumerate(sources):
        p=f"SOURCE_{i}"
        if not isinstance(s,dict): b.append(p+"_MALFORMED"); continue
        ref=s.get("ref")
        if not text(ref): b.append(p+"_REF_MISSING")
        elif ref in refs: b.append("DUPLICATE_SOURCE_REF")
        else: refs.add(ref)
        if s.get("required") is True:
            if s.get("read") is not True: r.append(p+"_NOT_READ")
            if not good_sha(s.get("declared_sha")) or not good_sha(s.get("observed_sha")): r.append(p+"_SHA_MISSING")
            elif s.get("declared_sha") != s.get("observed_sha"): r.append(p+"_SHA_MISMATCH")
            if s.get("current") is not True: r.append(p+"_STALE")
        if s.get("authority") is True:
            if s.get("derived_from_candidate") is True: b.append(p+"_SELF_CERTIFIED_AUTHORITY")
            elif s.get("relevance")=="MATERIAL": authority_declared=True
        if s.get("role")=="upstream":
            if s.get("validator_status") not in PASS_UPSTREAM: b.append(p+"_UPSTREAM_INVALID")
            if s.get("validator_current") is not True: b.append(p+"_UPSTREAM_VALIDATOR_STALE")
            if provenance_required and not text(s.get("receipt_id")): r.append(p+"_RECEIPT_MISSING")
        rid=s.get("receipt_id")
        if rid is not None:
            if not text(rid) or rid in receipts or s.get("receipt_replayed") is True: b.append("RECEIPT_REPLAY")
            else: receipts.add(rid)
            if s.get("receipt_subject_sha") != candidate_sha: b.append(p+"_RECEIPT_SUBJECT_MISMATCH")
    if sources and not authority_declared: b.append("INDEPENDENT_AUTHORITY_MISSING")
    if artifact_required and case.get("artifact_verified") is not True: r.append("ARTIFACT_NOT_VERIFIED")
    ids=case.get("structural_identifiers",[])
    if not isinstance(ids,list): b.append("STRUCTURAL_IDENTIFIERS_MALFORMED")
    else:
        for i,x in enumerate(ids):
            if not isinstance(x,dict) or x.get("reconciled") is not True: b.append(f"STRUCTURAL_IDENTIFIER_{i}_UNRECONCILED")
            elif x.get("observed") != x.get("canonical"): b.append(f"STRUCTURAL_IDENTIFIER_{i}_MISMATCH")
    conflicts=case.get("conflicts",[])
    if not isinstance(conflicts,list): b.append("CONFLICTS_MALFORMED")
    else:
        for i,x in enumerate(conflicts):
            if not isinstance(x,dict) or x.get("resolved") is not True: b.append(f"SOURCE_CONFLICT_{i}_UNRESOLVED")
    assertions=case.get("semantic_assertions")
    if not isinstance(assertions,list) or not assertions: b.append("INDEPENDENT_SEMANTIC_ASSERTIONS_MISSING")
    else:
        for i,a in enumerate(assertions):
            p=f"ASSERTION_{i}"
            if not isinstance(a,dict): b.append(p+"_MALFORMED"); continue
            if not text(a.get("authority_ref")): b.append(p+"_AUTHORITY_REF_MISSING")
            if a.get("oracle_id")==case.get("candidate_oracle_id"): b.append(p+"_CORRELATED_ORACLE")
            if a.get("derived_from_candidate") is True: b.append(p+"_SELF_DERIVED")
            if a.get("match") is not True: b.append(p+"_SEMANTIC_MISMATCH")
    status="BLOCK_PIPELINE" if b else ("RETURN_TO_SOURCE_FOR_READBACK" if r else "PASS_EVIDENCE_LINEAGE")
    provenance_issues=b+r
    return {"status":status,"blocking_codes":sorted(set(b)),"readback_codes":sorted(set(r)),"gate_states":{"STRUCTURALLY_VALID":not any("MALFORMED" in x or "INVALID" in x for x in b),"PROVENANCE_VALID":not any("RECEIPT" in x or "SHA" in x or "_STALE" in x or "_NOT_READ" in x for x in provenance_issues),"SEMANTICALLY_VALID":not any("ASSERTION" in x or "SEMANTIC" in x or "CORRELATED" in x or "AUTHORITY" in x or "CONFLICT" in x for x in b),"ARTIFACT_VERIFIED":case.get("artifact_verified") is True,"UPSTREAM_VALID":not any("UPSTREAM" in x for x in b)}}

def run_matrix(path):
    matrix=json.loads(Path(path).read_text())
    out=[]; failed=False
    for c in matrix.get("cases",[]):
        actual=evaluate(c.get("input")); code=c.get("expected_code")
        passed=actual["status"]==c.get("expected_status") and (code is None or code in actual["blocking_codes"]+actual["readback_codes"])
        failed|=not passed; out.append({"id":c.get("id"),"kind":c.get("kind"),"actual":actual,"passed":passed})
    digest=hashlib.sha256(json.dumps(out,sort_keys=True).encode()).hexdigest()
    print(json.dumps({"passed":not failed,"case_count":len(out),"results_sha256":digest,"results":out},indent=2)); return 1 if failed else 0

def main():
    p=argparse.ArgumentParser(); p.add_argument("case",nargs="?"); p.add_argument("--matrix"); a=p.parse_args()
    if bool(a.case)==bool(a.matrix): p.error("provide exactly one case or --matrix")
    if a.matrix: return run_matrix(a.matrix)
    result=evaluate(json.loads(Path(a.case).read_text())); print(json.dumps(result,indent=2)); return 0 if result["status"]=="PASS_EVIDENCE_LINEAGE" else 1
if __name__=="__main__": sys.exit(main())
