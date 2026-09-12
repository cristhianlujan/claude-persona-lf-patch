from __future__ import annotations
import copy, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from s30_strategy_executor_bootstrap import *

def load(name): return json.loads((HERE/name).read_text())

def main():
    checks=0
    bootstrap=load('strategy_executor_bootstrap_contract_v1.json')
    activation=load('strategy_executor_sandbox_activation_contract_v1.json')
    canary=load('strategy_executor_live_canary_v1.json')
    assert validate_sandbox_activation_contract(activation,bootstrap)['status']==PASS; checks+=1
    bad=copy.deepcopy(activation); bad['router_binding']['write_allowed']=True
    assert validate_sandbox_activation_contract(bad,bootstrap)['code']=='BLOCK_EXECUTOR_SANDBOX_ROUTER_BINDING'; checks+=1
    bad=copy.deepcopy(activation); bad['strategy_resolution']['authority']='public.lf_activos'
    assert validate_sandbox_activation_contract(bad,bootstrap)['code']=='BLOCK_EXECUTOR_SANDBOX_STRATEGY_AUTHORITY'; checks+=1
    bad=copy.deepcopy(activation); bad['canary_boundary']['business_effect_dispatch_allowed']=True
    assert validate_sandbox_activation_contract(bad,bootstrap)['code']=='BLOCK_EXECUTOR_SANDBOX_CANARY_BOUNDARY'; checks+=1
    bad=copy.deepcopy(activation); bad['canary_boundary']['scheduler_activation']=True
    assert validate_sandbox_activation_contract(bad,bootstrap)['code']=='BLOCK_EXECUTOR_SANDBOX_FORBIDDEN_ACTIVATION'; checks+=1
    plan=build_sandbox_materialization_plan(bootstrap,activation)
    assert plan['status']==PASS and len(plan['steps'])==15; checks+=1
    assert validate_sandbox_materialization_plan(plan,bootstrap)['status']==PASS; checks+=1
    assert all('runtime_activation' not in s['pass_condition'] for s in plan['steps']); checks+=1
    assert all('runtime_activation_attempt' not in s['block_condition'] for s in plan['steps']); checks+=1
    assert all(s['pass_condition']['runtime_activation_authorized'] is True for s in plan['steps']); checks+=1
    badplan=copy.deepcopy(plan); badplan['steps'][0]['pass_condition']['runtime_activation']=False
    assert validate_sandbox_materialization_plan(badplan,bootstrap)['code']=='BLOCK_EXECUTOR_SANDBOX_BOOTSTRAP_PREDICATE_LEAK'; checks+=1
    assert validate_live_canary_blueprint(canary,activation)['status']==PASS; checks+=1
    bad=copy.deepcopy(canary); bad['finding_quota']=10
    assert validate_live_canary_blueprint(bad,activation)['code']=='BLOCK_EXECUTOR_LIVE_CANARY_QUALITY_POLICY'; checks+=1
    bad=copy.deepcopy(canary); bad['checks']=bad['checks'][:-1]
    assert validate_live_canary_blueprint(bad,activation)['code']=='BLOCK_EXECUTOR_LIVE_CANARY_COVERAGE'; checks+=1
    print(json.dumps({'result':'PASS','contract':'S30_STRATEGY_EXECUTOR_SANDBOX_ACTIVATION_V1','checks':checks,'projected_steps':15,'business_effect_dispatch_allowed':False,'model_calls_allowed':False,'orchestrator_activation':False,'scheduler_activation':False,'production_activation':False,'s26_mutation':False},sort_keys=True))

if __name__=='__main__': main()
