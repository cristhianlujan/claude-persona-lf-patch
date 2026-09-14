#!/usr/bin/env python3
import json, subprocess, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parent
ROUTER=ROOT/'lf_s38_s36_assurance_router_v1.py'
ROUTING=ROOT/'lf_transversal_strategy_routing_v1.json'
SIGNER='b'*40
BREF='github://cristhianlujan/claude-persona-lf-patch@'+'a'*40+'/bundle.json'

def bundle():
    return {
      'review_case_id':'S38-DG-IR-008','execution_mode':'INDEPENDENT_CHAT_CONTEXT','producer_semantic_verdict':None,
      'candidate_snapshot':{'s38_candidate_head':'c'*40},
      'external_trust':{'expected_signer_digest_out_of_band':SIGNER,'signer_workflow_ref':'github://repo@'+SIGNER+'/signer.yml','runtime_network_required_after_verified_subject_bootstrap':False},
      'current_candidate_pins':[{'x':1}]*11,'historical_frozen_artifacts':[{'x':1}]*16,'frozen_quality_pack':[{'x':1}]*2,
      'authority':{'merge':'NONE','golden':'NONE','runtime':'NONE','scheduler':'NONE','production':'NONE','promotion':'NONE'}
    }

def receipt(verdict='PASS_WITH_RESTRICTIONS'):
    return {'review_case_id':'S38-DG-IR-008','execution_mode':'INDEPENDENT_CHAT_CONTEXT','semantic_status':'EXECUTED_INDEPENDENT_CONTEXT','reviewer_is_producer':False,'producer_context_available':False,'review_completed':True,'execution_blockers':[],
      'source_bundle':{'artifact_ref':BREF},'quality_review':{'reviewed_artifact':BREF,'verdict':verdict,'blocking_codes':['R1'] if verdict=='PASS_WITH_RESTRICTIONS' else []}}

def run(b, r='ABSENT', signer=SIGNER):
    with tempfile.TemporaryDirectory() as td:
        td=Path(td); bp=td/'b.json'; op=td/'o.json'; bp.write_text(json.dumps(b))
        cmd=['python3',str(ROUTER),'--bundle',str(bp),'--bundle-ref',BREF,'--expected-signer-digest',signer,'--routing-contract',str(ROUTING),'--output',str(op)]
        if r!='ABSENT':
            rp=td/'r.json'; rp.write_text(json.dumps(r)); cmd += ['--receipt',str(rp)]
        p=subprocess.run(cmd,text=True,capture_output=True)
        doc=json.loads(op.read_text())
        return p.returncode,doc

def check(name, cond):
    if not cond: raise AssertionError(name)
    print('PASS',name)

rc,d=run(bundle()); check('WAIT_NO_RECEIPT', rc==0 and d['route_state']=='WAIT_INDEPENDENT_REVIEW' and d['route_to']=='S38')
rc,d=run(bundle(),receipt('PASS_TO_COMPOSER')); check('PASS_TO_S36', rc==0 and d['route_state']=='READY_FOR_S36_ASSURANCE_ENROLLMENT' and d['route_to']=='S36')
rc,d=run(bundle(),receipt('PASS_WITH_RESTRICTIONS')); check('RESTRICTED_TO_S36', rc==0 and d['route_state'].endswith('WITH_RESTRICTIONS') and d['route_to']=='S36')
rc,d=run(bundle(),receipt('RETURN_TO_WORKER_FOR_SELF_REPAIR')); check('RETURN_TO_S38', rc==0 and d['route_state']=='RETURN_TO_S38_REPAIR')
b=bundle(); b['producer_semantic_verdict']='PASS'; rc,d=run(b); check('PRODUCER_VERDICT_BLOCKED', rc==2 and d['blocking_reason']=='BLOCK_PRODUCER_SEMANTIC_VERDICT_NOT_NULL')
rc,d=run(bundle(),receipt(),signer='d'*40); check('WRONG_SIGNER_BLOCKED', rc==2 and d['blocking_reason']=='BLOCK_OUT_OF_BAND_SIGNER_DIGEST_MISMATCH')
r=receipt(); r['producer_context_available']=True; rc,d=run(bundle(),r); check('NONINDEPENDENT_RECEIPT_BLOCKED', rc==2 and d['blocking_reason']=='BLOCK_RECEIPT_INDEPENDENCE_INVALID')
b=bundle(); b['authority']['runtime']='GRANTED'; rc,d=run(b); check('AUTHORITY_ESCALATION_BLOCKED', rc==2 and d['blocking_reason']=='BLOCK_S38_PACKAGE_AUTHORITY_ESCALATION')
print('RESULT=PASS_S38_S36_ASSURANCE_ROUTER_V1')
