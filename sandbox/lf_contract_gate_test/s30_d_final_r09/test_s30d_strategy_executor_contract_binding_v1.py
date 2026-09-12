from __future__ import annotations
import copy, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from s30_strategy_executor_contract_binding_v1 import PASS, validate_contract_binding_v1

def load(name): return json.loads((HERE/name).read_text(encoding='utf-8'))

def main():
    manifest=load('strategy_executor_contract_binding_v1.json')
    activation=load('strategy_executor_sandbox_activation_contract_v3.json')
    matrix=load('strategy_executor_family_objective_matrix_v4.json')
    canary=load('strategy_executor_live_canary_v6.json')
    perf=load('strategy_executor_performance_policy_v1.json')
    checks=0
    r=validate_contract_binding_v1(manifest,activation,matrix,canary,perf)
    assert r['status']==PASS,r; checks+=1
    bad=copy.deepcopy(manifest); bad['components']['activation']['expected_version']='S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V2'
    assert validate_contract_binding_v1(bad,activation,matrix,canary,perf)['code']=='BLOCK_STALE_BINDING'; checks+=1
    bad=copy.deepcopy(matrix); bad['activation_contract']='S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V3'
    assert validate_contract_binding_v1(manifest,activation,bad,canary,perf)['code']=='BLOCK_DUPLICATED_VERSION_AUTHORITY'; checks+=1
    bad=copy.deepcopy(canary); bad['family_matrix_binding']='S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V4'
    assert validate_contract_binding_v1(manifest,activation,matrix,bad,perf)['code']=='BLOCK_DUPLICATED_VERSION_AUTHORITY'; checks+=1
    bad=copy.deepcopy(canary); bad['contract_binding_manifest']='OTHER'
    assert validate_contract_binding_v1(manifest,activation,matrix,bad,perf)['code']=='BLOCK_BINDING_COMPONENT_MANIFEST_REF'; checks+=1
    bad=copy.deepcopy(perf); bad['policy_version']='S30_STRATEGY_EXECUTOR_PERFORMANCE_POLICY_V2'
    assert validate_contract_binding_v1(manifest,activation,matrix,canary,bad)['code']=='BLOCK_STALE_BINDING'; checks+=1
    bad=copy.deepcopy(canary); bad['production_write_allowed']=True
    assert validate_contract_binding_v1(manifest,activation,matrix,bad,perf)['code']=='BLOCK_BINDING_CANARY_ZERO_EFFECT'; checks+=1
    print(json.dumps({'result':'PASS','contract':'S30_STRATEGY_EXECUTOR_CONTRACT_BINDING_V1','checks':checks,'duplicated_version_authority':False},sort_keys=True))
if __name__=='__main__': main()
