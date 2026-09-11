from __future__ import annotations
import copy, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from s30_strategy_executor_bootstrap import *

def load(name):
    return json.loads((HERE/name).read_text())

def main():
    checks=0
    c=load("strategy_executor_bootstrap_contract_v1.json")
    m=load("strategy_executor_registration_manifest_v1.json")
    b=load("strategy_executor_canary_blueprint_v1.json")
    assert validate_bootstrap_contract(c)["status"]==PASS; checks+=1
    bad=copy.deepcopy(c); bad["target_cardinality"]="MULTI"; assert validate_bootstrap_contract(bad)["code"]=="BLOCK_EXECUTOR_CARDINALITY"; checks+=1
    bad=copy.deepcopy(c); bad["runtime_activation"]=True; assert validate_bootstrap_contract(bad)["code"]=="BLOCK_EXECUTOR_BOOTSTRAP_SIDE_EFFECT"; checks+=1
    bad=copy.deepcopy(c); bad["steps"][5],bad["steps"][6]=bad["steps"][6],bad["steps"][5]; assert validate_bootstrap_contract(bad)["code"]=="BLOCK_EXECUTOR_STEP_SEQUENCE"; checks+=1
    bad=copy.deepcopy(c); bad["mandatory_invariants"].remove("NO_EFFECT_BEFORE_EFFECT_GUARD_RESERVATION"); assert validate_bootstrap_contract(bad)["code"]=="BLOCK_EXECUTOR_INVARIANT_MISSING"; checks+=1
    assert validate_registration_manifest(m)["status"]==PASS; checks+=1
    bad=copy.deepcopy(m); bad["apply_actions"]["operation_registry_write"]=True; assert validate_registration_manifest(bad)["code"]=="BLOCK_EXECUTOR_REGISTRATION_SIDE_EFFECT"; checks+=1
    ctx={"c05_dynamic_pass":True,"c05_source_parity_durable":True,"r16_durable":True,"typed_data_access_available":True,"fresh_schema_readback":True,"operation_code_absent":True,"owner_registration_authorized":False}
    r=registration_readiness(ctx); assert r["code"]=="READY_FOR_REGISTRATION_AUTHORIZATION" and r["registration_allowed"] is False; checks+=1
    badctx=dict(ctx); badctx["fresh_schema_readback"]=False; assert registration_readiness(badctx)["code"]=="BLOCK_EXECUTOR_REGISTRATION_PRECONDITION"; checks+=1
    auth=dict(ctx); auth["owner_registration_authorized"]=True; r=registration_readiness(auth); assert r["registration_allowed"] is True and r["runtime_activation_allowed"] is False; checks+=1
    assert b["case_count"]==len(b["cases"])==12 and b["backend_writes"]==0; checks+=1
    for case in b["cases"]:
        assert simulate_canary(case)==case["expected"],case; checks+=1
    unknown={"fault":"UNLISTED"}; assert simulate_canary(unknown)=="BLOCK_UNKNOWN_CANARY_FAULT"; checks+=1
    assert c["scheduler_activation"] is False and c["production_activation"] is False and c["s26_mutation"] is False; checks+=1
    print(json.dumps({"result":"PASS","contract":"S30_STRATEGY_EXECUTOR_BOOTSTRAP_V1","checks":checks,"canary_cases":12,"backend_writes":0,"runtime_activation":False,"scheduler_activation":False,"production_activation":False,"s26_mutations":0},sort_keys=True))

if __name__=="__main__": main()
