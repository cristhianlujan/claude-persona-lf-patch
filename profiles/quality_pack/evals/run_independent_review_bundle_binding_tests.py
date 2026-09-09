#!/usr/bin/env python3
import copy
import json
import shutil
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'profiles/quality_pack/validators'))
from validate_independent_review_bundle_receipt import validate

with tempfile.TemporaryDirectory() as td:
    b=Path(td)
    (b/'validators').mkdir()
    shutil.copy2(ROOT/'profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json',b/'independent_semantic_review_receipt.schema.json')
    shutil.copy2(ROOT/'profiles/quality_pack/schemas/quality_review.schema.json',b/'quality_review.schema.json')
    shutil.copy2(ROOT/'profiles/quality_pack/validators/validate_independent_semantic_review.py',b/'validators/validate_independent_semantic_review.py')
    shutil.copy2(ROOT/'profiles/quality_pack/validators/validate_routing.py',b/'validators/validate_routing.py')
    for name in ['artifact_payload.json','upstream_existing_screen_review_contract.md','quality_gate_contract.md','lf_quality_controls.md','quality_pack_score_rubric.md','quality_pack_mini_judge.md','source_visual.png','composer_payload_boundary_v1.md']:
        (b/name).write_text('{}' if name.endswith('.json') else 'fixture',encoding='utf-8')
    case={'review_case_id':'CASE-001','artifact_ref':'bundle://artifact_payload.json','artifact_canonical_sha256':'a'*64,'upstream_worker_contract_ref':'bundle://upstream_existing_screen_review_contract.md'}
    (b/'review_case.json').write_text(json.dumps(case),encoding='utf-8')
    review={
      'review_id':'CASE-001-TEST','reviewed_artifact':'bundle://artifact_payload.json#sha256='+'a'*64,
      'verdict':'PASS_TO_COMPOSER','score_breakdown':{'contract_schema_compliance':5,'evidence_integrity':5,'lf_safety_governance':5,'handoff_readiness':5,'leakage_scope_control':5,'total':25},
      'evidence_map':[
       {'criterion':'contract_schema_compliance','refs':['bundle://artifact_payload.json'],'observed':'ok'},
       {'criterion':'evidence_integrity','refs':['bundle://source_visual.png'],'observed':'ok'},
       {'criterion':'lf_safety_governance','refs':['bundle://lf_quality_controls.md'],'observed':'ok'},
       {'criterion':'handoff_readiness','refs':['bundle://upstream_existing_screen_review_contract.md'],'observed':'ok'},
       {'criterion':'leakage_scope_control','refs':['bundle://composer_payload_boundary_v1.md'],'observed':'ok'}],
      'blocking_codes':[],'repair_actions':[],'remaining_risks':[],'next_gate':'ORCHESTRATOR',
      'routing':{'activation_path':'DIRECT','via':'ORCHESTRATOR','pipeline_action':'CONTINUE','resolution_target':'COMPOSER'}}
    receipt={
      'receipt_version':'v0.1','execution_mode':'INDEPENDENT_CHAT_CONTEXT','semantic_status':'EXECUTED_INDEPENDENT_CONTEXT','review_case_id':'CASE-001',
      'reviewer_is_producer':False,'producer_context_available':False,'external_paid_model_used':False,'automated_semantic_judge_implemented':False,'review_completed':True,
      'source_bundle':{'artifact_ref':'bundle://artifact_payload.json','artifact_sha_or_digest':'a'*64,'upstream_worker_contract_ref':'bundle://upstream_existing_screen_review_contract.md','quality_gate_contract_ref':'bundle://quality_gate_contract.md','lf_quality_controls_ref':'bundle://lf_quality_controls.md','score_rubric_ref':'bundle://quality_pack_score_rubric.md','mini_judge_ref':'bundle://quality_pack_mini_judge.md','quality_review_schema_ref':'bundle://quality_review.schema.json'},
      'quality_review':review,'execution_blockers':[]}

    def run(name,value,expected):
        errors=validate(value,b); actual=not errors
        assert actual==expected,(name,errors)
        print('PASS',name,'valid='+str(actual))

    run('base',receipt,True)
    x=copy.deepcopy(receipt);x['source_bundle']['artifact_sha_or_digest']='0'*64;run('wrong_sha',x,False)
    x=copy.deepcopy(receipt);x['review_case_id']='OLD';run('wrong_case',x,False)
    x=copy.deepcopy(receipt);del x['quality_review']['routing'];run('missing_routing',x,False)
    x=copy.deepcopy(receipt);x['quality_review']['evidence_map'][0]['refs']=['github://x/y@'+'0'*40+'/a'];run('external_ref',x,False)
    x=copy.deepcopy(receipt);x['quality_review']['evidence_map']=x['quality_review']['evidence_map'][:-1];run('coverage_missing',x,False)
    x=copy.deepcopy(receipt);x['extra']='x';run('extra_key',x,False)
    print('INDEPENDENT_REVIEW_BUNDLE_BINDING_REGRESSIONS_PASS=7/7')
