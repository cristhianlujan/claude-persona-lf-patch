from __future__ import annotations
import copy, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from s30_strategy_executor_family_assurance_v4 import PASS, validate_family_objective_matrix_v4

def load(name): return json.loads((HERE/name).read_text(encoding='utf-8'))

def main():
    manifest=load('strategy_executor_contract_binding_v1.json')
    activation=load('strategy_executor_sandbox_activation_contract_v3.json')
    matrix=load('strategy_executor_family_objective_matrix_v4.json')
    canary=load('strategy_executor_live_canary_v6.json')
    perf=load('strategy_executor_performance_policy_v1.json')
    checks=0
    r=validate_family_objective_matrix_v4(manifest,matrix,activation,canary,perf)
    assert r['status']==PASS,r; assert r['objective_count']==14; assert r['performance_metric_count']==9; checks+=1
    bad=copy.deepcopy(matrix); bad['objective_dimension_profiles']=bad['objective_dimension_profiles'][:-1]
    assert validate_family_objective_matrix_v4(manifest,bad,activation,canary,perf)['code']=='BLOCK_V4_DIMENSION_PROFILE_COVERAGE'; checks+=1
    bad=copy.deepcopy(matrix); bad['runtime_canary_contract']='S30_STRATEGY_EXECUTOR_LIVE_CANARY_V6'
    out=validate_family_objective_matrix_v4(manifest,bad,activation,canary,perf)
    assert out['code']=='BLOCK_V4_CONTRACT_BINDING' and out['binding_code']=='BLOCK_DUPLICATED_VERSION_AUTHORITY'; checks+=1
    bad=copy.deepcopy(perf); bad['sample_policy']['measured_samples_min']=1
    assert validate_family_objective_matrix_v4(manifest,matrix,activation,canary,bad)['code']=='BLOCK_V4_PERFORMANCE_SAMPLE_POLICY'; checks+=1
    bad=copy.deepcopy(canary); bad['dimension_checks']=bad['dimension_checks'][:-1]
    assert validate_family_objective_matrix_v4(manifest,matrix,activation,bad,perf)['code']=='BLOCK_V4_DIMENSION_CHECK_COVERAGE'; checks+=1
    bad=copy.deepcopy(manifest); bad['components']['live_canary']['expected_version']='S30_STRATEGY_EXECUTOR_LIVE_CANARY_V5'
    out=validate_family_objective_matrix_v4(bad,matrix,activation,canary,perf)
    assert out['code']=='BLOCK_V4_CONTRACT_BINDING' and out['binding_code']=='BLOCK_STALE_BINDING'; checks+=1
    print(json.dumps({'result':'PASS','contract':'S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V4','checks':checks,'objectives':14,'dimensions':4},sort_keys=True))
if __name__=='__main__': main()
