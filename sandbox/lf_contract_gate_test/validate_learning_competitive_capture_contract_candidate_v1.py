#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_competitive_capture_contract_candidate_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_COMPETITIVE_CAPTURE_CONTRACT_CANDIDATE_V1','SCHEMA')
req(D['status']=='CANDIDATE_READ_ONLY_NOT_CANONICAL','STATUS')
req(D['operation_code']=='BUILD_COMPETITIVE_INTELLIGENCE_MARKETPLACE_LF','OPERATION')
A=D['source_authority']
req(A['supabase_events']==[57,64,65,66,67,68,71],'SOURCE_EVENTS')
req(A['registry_version']=='v0.1' and A['registry_status']=='CANDIDATO_READ_ONLY','REGISTRY')
req(A['current_canonical_step_contract_count']==0,'NO_CANONICAL_STEPS')
M=set(D['mandatory_variables'])
req(M=={'execution_id','run_id','source_id','competitor_id','platform','last_checked_at','dedup_key','retry_count','rate_limit_status','capture_mode','environment'},'MANDATORY_VARIABLES')
S=D['selection_policy']
req(S['source_selection']=='EXACT_ACTIVE_SOURCE_ID_FROM_SBX_COMPETITIVE_SOURCES','EXACT_SOURCE')
req(S['url_selection']=='EXACT_REGISTERED_URL_ONLY','EXACT_URL')
req(S['free_semantic_search'] is False and S['llm_source_selection'] is False and S['automatic_source_discovery'] is False,'NO_AUTHORITY_EXPANSION')
steps=D['steps']
req(len(steps)==10 and [x['order'] for x in steps]==list(range(10,101,10)),'STEPS')
req(len({x['step_id'] for x in steps})==10 and all(x['judge'] and x['pass_if'] and x['blocked_if'] for x in steps),'STEP_CONTRACTS')
obs=next(x for x in steps if x['step_id']=='sandbox_observation_write')
state=next(x for x in steps if x['step_id']=='source_state_update')
req('candidate_contract_only' in obs['blocked_if'] and 'canonical_contract_missing' in obs['blocked_if'],'OBS_FAIL_CLOSED')
req('candidate_contract_only' in state['blocked_if'],'STATE_FAIL_CLOSED')
W=D['write_boundary']
req(W['current_candidate_contract_allows_writes'] is False,'NO_CURRENT_WRITES')
for k in ('canonical_kb_write','insight_auto_write','official_document_impact','production_authorized'):
    req(W[k] is False,'BOUNDARY_'+k.upper())
F=D['final_judge']
req(F['code']=='JUDGE_FINAL_COMPETITIVE_CAPTURE_CANDIDATE_FAIL_CLOSED_V1','FINAL_JUDGE')
req('candidate_contract_does_not_write' in F['pass_if'] and 'no_kb_write' in F['pass_if'] and 'no_automatic_promotion' in F['pass_if'],'FINAL_BOUNDARY')
req(D['current_outcome']=='PASS_CANDIDATE_NO_RUNTIME_AUTHORITY','OUTCOME')
req(D['next_gate']=='INDEPENDENT_REVIEW_AND_CANONICAL_OPERATION_STEP_CONTRACT_ACTIVATION_BEFORE_ANY_SANDBOX_OBSERVATION_WRITE','NEXT_GATE')
print('LEARNING_COMPETITIVE_CAPTURE_CONTRACT_CANDIDATE=PASS steps=10 writes=0 exact_selection=true production_authorized=false')
