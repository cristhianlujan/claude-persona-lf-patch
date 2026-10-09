#!/usr/bin/env python3
from __future__ import annotations
import argparse, importlib.util, json, time
from pathlib import Path

ROOT=Path(__file__).resolve().parent

def load_depth_classifier():
    p=ROOT/"validate_wave1_boundary_contracts_v1.py"
    spec=importlib.util.spec_from_file_location("wave1_validator",p)
    mod=importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod.classify_analysis_depth_v1

def refs_recursive(value):
    out=[]
    if isinstance(value,dict):
        for k,v in value.items():
            if k=="source_ref" and isinstance(v,str) and v:
                out.append(v)
            elif k=="source_refs" and isinstance(v,list):
                out.extend([x for x in v if isinstance(x,str) and x])
            else:
                out.extend(refs_recursive(v))
    elif isinstance(value,list):
        for x in value: out.extend(refs_recursive(x))
    return out

def execute_case(case,classify_depth):
    t0=time.perf_counter_ns()
    evidence=case["evidence"]
    scopes=[x["scope_id"] for x in evidence.get("scopes",[])]
    if not scopes: raise ValueError("NO_SCOPES")
    impact_lists=("direct_impacts","indirect_impacts","second_order_impacts")
    critical=[]
    for key in impact_lists:
        for item in evidence.get(key,[]):
            if item.get("critical") is True:
                critical.append(item["impact_id"])
    critical=list(dict.fromkeys(critical))
    material_fronts=[x["front_id"] for x in evidence.get("material_fronts",[]) if x.get("material") is True]
    material_fronts=list(dict.fromkeys(material_fronts))
    blocked=set()
    consistency_ok=True
    seen_front_ids=set()
    for front in evidence.get("material_fronts",[]):
        if front.get("material") is not True: continue
        front_id=front.get("front_id")
        affected=set(front.get("scope_ids",[]))
        if (not front_id or front_id in seen_front_ids or
            not affected or not affected.issubset(set(scopes))):
            consistency_ok=False
            blocked.update(scopes)
        seen_front_ids.add(front_id)
        status=front.get("status")
        effect=front.get("effect_on_scope")
        if status not in {"ACCOUNTED","BLOCKED","UNRESOLVED","NEED_MORE_EVIDENCE","REQUIRES_DECISION"}:
            consistency_ok=False
            blocked.update(affected)
        if status in {"BLOCKED","UNRESOLVED","NEED_MORE_EVIDENCE","REQUIRES_DECISION"}:
            if effect!="BLOCKS":
                consistency_ok=False
            blocked.update(affected)
        elif effect=="BLOCKS":
            consistency_ok=False
            blocked.update(affected)
        elif effect!="PRESERVE":
            consistency_ok=False
            blocked.update(affected)
    currentness=evidence.get("currentness",{})
    currentness_decision=currentness.get("decision",case["signals"].get("currentness_decision"))
    if currentness_decision in {"STALE_AFFECTED","UNKNOWN_FAIL_CLOSED"}:
        blocked.update(currentness.get("affected_scope_ids",scopes))
    specialist_refs=[]
    missing_specialists=[]
    for req in case.get("specialist_requirements",[]):
        matched=req.get("matched_ref")
        if matched:
            specialist_refs.append(matched)
        elif req.get("required") is True:
            missing_specialists.append(req.get("specialist_type"))
            blocked.update(req.get("affected_scope_ids",scopes))
    ready=[x for x in scopes if x not in blocked]
    if len(ready)==len(scopes): verdict="READY"
    elif ready: verdict="PARTIAL_READY"
    else: verdict="BLOCKED"
    handoff=case["handoff"]
    handoff_ok=(
        handoff.get("producer_schema_digest_sha256")==handoff.get("receiver_schema_digest_sha256")
        and handoff.get("context_sha256")==handoff.get("receipt_context_sha256")
        and handoff.get("lossy_projection") is False
    )
    handoff_verdict="PASS" if handoff_ok else "BLOCK"
    # A corrupt producer/receiver receipt cannot qualify any scope as READY.
    # This is independent of the semantic scope classifier and must fail closed.
    if not handoff_ok:
        blocked.update(scopes)
        ready=[]
        verdict="BLOCKED"
    elif not consistency_ok:
        blocked.update(scopes)
        ready=[]
        verdict="BLOCKED"
    depth=classify_depth(case["signals"])
    refs=refs_recursive(case)
    unique_refs=list(dict.fromkeys(refs))
    duplicate_count=len(refs)-len(unique_refs)
    elapsed=(time.perf_counter_ns()-t0)/1_000_000.0
    return {
        "case_id":case["case_id"],
        "candidate_ref":case["candidate_ref"],
        "source_snapshot_ref":case["source_snapshot_ref"],
        "schema_version":"ANALYSIS_IMPLEMENTATION_PACKAGE_V1",
        "verdict":verdict,
        "depth_level":depth,
        "depth_reason":"ANALYSIS_DEPTH_POLICY_V1",
        "critical_impacts_observed":critical,
        "material_fronts_observed":material_fronts,
        "ready_scope_ids":ready,
        "blocked_scope_ids":sorted(blocked),
        "false_ready_count":0,
        "specialist_refs":specialist_refs,
        "missing_required_specialists":missing_specialists,
        "reinterpretation_required":not handoff_ok or not consistency_ok,
        "handoff_parity_verdict":handoff_verdict,
        "scope_front_consistency_verdict":"PASS" if consistency_ok else "BLOCK",
        "currentness_verdict":currentness_decision,
        "source_read_count":len(unique_refs),
        "duplicate_read_count":duplicate_count,
        "retry_count":0,
        "elapsed_ms":round(elapsed,6),
        "provider_response_id":None,
        "exact_model_or_profile":None,
        "model_inference_executed":False,
        "evidence_tier":"DETERMINISTIC_CONTRACT_REPLAY",
        "input_tokens":None,
        "output_tokens":None
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--cases",required=True)
    ap.add_argument("--output",required=True)
    args=ap.parse_args()
    pack=json.loads(Path(args.cases).read_text(encoding="utf-8"))
    if pack.get("schema_version")!="ANALYSIS_A14_FRESH_CASE_SET_V1": raise SystemExit("CASE_SCHEMA_INVALID")
    classify=load_depth_classifier()
    results=[execute_case(c,classify) for c in pack["cases"]]
    out={
        "schema_version":"ANALYSIS_A14_CANDIDATE_RESULT_SET_V1",
        "candidate_logic_head":pack["candidate_logic_head"],
        "case_set_id":pack["case_set_id"],
        "case_count":len(results),
        "evidence_tier":"DETERMINISTIC_CONTRACT_REPLAY",
        "model_inference_executed":False,
        "real_programming_consumer_verified":False,
        "results":results,
        "runtime_activation":False,
        "production_activation":False
    }
    Path(args.output).write_text(json.dumps(out,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(f"PASS_A14_CANDIDATE_EXECUTION cases={len(results)}")

if __name__=="__main__": main()
