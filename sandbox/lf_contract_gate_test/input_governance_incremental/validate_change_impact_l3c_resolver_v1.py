#!/usr/bin/env python3
"""Evaluate READ_ONLY change-impact resolver against independently adjudicated gold."""
from __future__ import annotations
import json, statistics, sys, time
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from change_impact_l3c_resolver_readonly_v1 import resolve_change
INPUTS=HERE/'change_impact_l3c_structured_inputs_v1.json'
GOLD=HERE/'change_impact_l3c_adjudicated_gold_v2.json'
LOCAL={'SCOPED_CANDIDATE','SCOPED_BLOCK'}
NONLOCAL={'GLOBAL_ESCALATE','HUMAN_REQUIRED'}

def pct(xs,p):
    xs=sorted(xs); pos=(len(xs)-1)*p; lo=int(pos); hi=min(lo+1,len(xs)-1); f=pos-lo
    return xs[lo]*(1-f)+xs[hi]*f if xs else 0.0

def main():
    inp=json.loads(INPUTS.read_text()); gold_doc=json.loads(GOLD.read_text()); cases=inp['cases']; gold={x['case_id']:x for x in gold_doc['cases']}
    forbidden=set(inp['anti_leakage']['forbidden_input_fields']); leakage=[]
    for row in cases:
        overlap=forbidden.intersection(row)|forbidden.intersection(row.get('facts',{}))
        if overlap: leakage.append({'case_id':row.get('case_id'),'fields':sorted(overlap)})
    dec=imp=tp=fp=fn=under=over=0; depths=[]; failures=[]
    for row in cases:
        actual=resolve_change({'subject_kind':row['subject_kind'],'change_kind':row['change_kind'],'facts':row['facts']})
        exp=gold[row['case_id']]; ei=set(exp['impact_families']); ai=set(actual['impact_families'])
        dok=actual['decision']==exp['decision']; iok=ai==ei; dec+=dok; imp+=iok; tp+=len(ai&ei); fp+=len(ai-ei); fn+=len(ei-ai); depths.append(actual['evidence_depth'])
        under += int(exp['decision'] in NONLOCAL and actual['decision'] in LOCAL)
        over += int(exp['decision'] in LOCAL and actual['decision']=='GLOBAL_ESCALATE')
        if not dok or not iok: failures.append({'case_id':row['case_id'],'decision_ok':dok,'impact_ok':iok,'expected_decision':exp['decision'],'actual_decision':actual['decision']})
    adversarial=[
      ({'subject_kind':'unknown','change_kind':'NO_CHANGE','facts':{'canonical_authority':'EXACT_CURRENT'}},'GLOBAL_ESCALATE'),
      ({'subject_kind':'field','change_kind':'UNKNOWN','facts':{'canonical_authority':'EXACT_CURRENT'}},'GLOBAL_ESCALATE'),
      ({'subject_kind':'field','change_kind':'MIXED','facts':{'canonical_authority':'EXACT_CURRENT'}},'GLOBAL_ESCALATE'),
      ({'subject_kind':'copy','change_kind':'CANONICAL_RECONCILIATION','facts':{'canonical_authority':'EXACT_CURRENT','shared_dependency_status':'UNKNOWN'}},'GLOBAL_ESCALATE'),
      ({'subject_kind':'action','change_kind':'NO_CHANGE','facts':{'canonical_authority':'EXACT_CURRENT','shared_dependency_status':'STALE'}},'GLOBAL_ESCALATE'),
      ({'subject_kind':'permission','change_kind':'NO_CHANGE','facts':{'canonical_authority':'EXACT_CURRENT','shared_dependency_status':'CONFLICT'}},'GLOBAL_ESCALATE'),
      ({'subject_kind':'route','change_kind':'ADD_NEW_SEMANTICS','facts':{'canonical_authority':'MISSING'}},'HUMAN_REQUIRED'),
      ({'subject_kind':'copy','change_kind':'CANONICAL_RECONCILIATION','facts':{'canonical_authority':'EXACT_CURRENT','visual_change':True}},'SCOPED_CANDIDATE'),
      ({'subject_kind':'copy','change_kind':'NON_SEMANTIC_FORMAT','facts':{'canonical_authority':'EXACT_CURRENT','visual_change':True}},'SCOPED_CANDIDATE'),
      ({'subject_kind':'component','change_kind':'DEPRECATED_REFERENCE','facts':{'canonical_authority':'DEPRECATED','local_invalidity':True}},'SCOPED_BLOCK')]
    adv=sum(resolve_change(x)['decision']==want for x,want in adversarial)
    perf=[]
    for _ in range(100):
        for row in cases:
            x={'subject_kind':row['subject_kind'],'change_kind':row['change_kind'],'facts':row['facts']}; t=time.perf_counter_ns(); resolve_change(x); perf.append((time.perf_counter_ns()-t)/1_000_000.0)
    out={'schema':'INPUT_GOV_CHANGE_IMPACT_L3C_RESOLVER_EVAL_V1','benchmark':gold_doc['base_gold']['benchmark'],'authority':gold_doc['authority'],'cases':len(cases),'exact_decision_accuracy':dec/len(cases),'exact_decision_passed':dec,'exact_impact_set_accuracy':imp/len(cases),'exact_impact_set_passed':imp,'impact_precision_micro':tp/(tp+fp) if tp+fp else 1.0,'impact_recall_micro':tp/(tp+fn) if tp+fn else 1.0,'unsafe_under_block':under,'unnecessary_global_block':over,'unknown_mixed_shared_fail_closed':{'passed':adv,'total':len(adversarial)},'latency_ms':{'p50':pct(perf,.5),'p95':pct(perf,.95),'max':max(perf),'samples':len(perf)},'evidence_depth':{'min':min(depths),'p50':statistics.median(depths),'max':max(depths)},'anti_leakage':{'forbidden_fields_found':leakage,'case_id_removed_before_resolver':True,'case_family_removed_before_resolver':True},'authorization':{'scoped_pass_authorized':False,'downstream_authorized':False,'production_authorized':False},'failures':failures}
    print(json.dumps(out,sort_keys=True,indent=2))
    ok=len(cases)==50 and dec==50 and imp==50 and under==0 and adv==len(adversarial) and not leakage
    return 0 if ok else 2
if __name__=='__main__': raise SystemExit(main())
