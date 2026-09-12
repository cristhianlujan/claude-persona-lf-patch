from __future__ import annotations
import copy, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from s30_strategy_executor_precanary_currentness_v3 import PASS, evaluate_authority_currentness_v3, validate_precanary_source_contract_v3

def load(name): return json.loads((HERE/name).read_text(encoding='utf-8'))

def fresh_positive():
    return {'authority':'public.lf_strategy_snapshots','identity_field':'snapshot_code','selector':{'snapshot_code':'LF_OPERATING_CONSTITUTION_POLICY_AUTONOMOUS_OPERATIONS_20260906','matching':'EXACT'},'exact_match_count':1,'exact_matches':[{'id':35,'snapshot_code':'LF_OPERATING_CONSTITUTION_POLICY_AUTONOMOUS_OPERATIONS_20260906','status':'CANDIDATO_READ_ONLY','runtime_state':'PLAN_ONLY','impact_policy':'BLOQUEADO'}],'currentness_scope':'IMMEDIATE_PRE_RUNTIME','readback_current_for_execution':True,'observed_at':'2026-09-12T07:00:00+00:00'}

def main():
    manifest=load('strategy_executor_contract_binding_v1.json')
    activation=load('strategy_executor_sandbox_activation_contract_v3.json')
    matrix=load('strategy_executor_family_objective_matrix_v4.json')
    canary=load('strategy_executor_live_canary_v6.json')
    perf=load('strategy_executor_performance_policy_v1.json')
    frozen=load('strategy_executor_authority_readback_20260912_v2.json')
    checks=0
    r=validate_precanary_source_contract_v3(manifest,activation,matrix,canary,perf,frozen)
    assert r['status']==PASS,r; checks+=1
    ready=evaluate_authority_currentness_v3(activation,fresh_positive())
    assert ready['status']==PASS and ready['code']=='READY_FOR_RUNTIME_AUTHORIZATION_REQUEST'; checks+=1
    stale=fresh_positive(); stale['currentness_scope']='FROZEN_SOURCE_IDENTITY_EVIDENCE_NOT_EXECUTION_AUTHORITY'; stale['readback_current_for_execution']=False
    assert evaluate_authority_currentness_v3(activation,stale)['code']=='BLOCK_AUTHORITY_CURRENTNESS_STALE'; checks+=1
    ambiguous=fresh_positive(); ambiguous['exact_matches'].append(copy.deepcopy(ambiguous['exact_matches'][0])); ambiguous['exact_matches'][1]['id']=36; ambiguous['exact_match_count']=2
    assert evaluate_authority_currentness_v3(activation,ambiguous)['code']=='BLOCK_AUTHORITY_AMBIGUOUS'; checks+=1
    bad=copy.deepcopy(manifest); bad['components']['family_matrix']['expected_version']='S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3'
    out=validate_precanary_source_contract_v3(bad,activation,matrix,canary,perf,frozen)
    assert out['code']=='BLOCK_CURRENTNESS_V3_CONTRACT_BINDING' and out['binding_code']=='BLOCK_STALE_BINDING'; checks+=1
    bad=copy.deepcopy(canary); bad['production_write_allowed']=True
    out=validate_precanary_source_contract_v3(manifest,activation,matrix,bad,perf,frozen)
    assert out['code']=='BLOCK_CURRENTNESS_V3_CONTRACT_BINDING'; checks+=1
    print(json.dumps({'result':'PASS','contract':'S30_STRATEGY_EXECUTOR_PRECANARY_CURRENTNESS_V3','checks':checks,'runtime_activation_authorized':False},sort_keys=True))
if __name__=='__main__': main()
