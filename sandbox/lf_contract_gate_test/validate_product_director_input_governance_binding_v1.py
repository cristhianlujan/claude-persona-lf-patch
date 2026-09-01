#!/usr/bin/env python3
from __future__ import annotations
import copy
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "sandbox" / "lf_contract_gate_test"
sys.path.insert(0, str(RUNTIME_DIR))
from product_director_input_governance_binding_v1 import GovernanceBindingError, build_bound_governance_receipt, validate_bound_governance_receipt
REQUEST_ID = "req-pd-001"
PROFILE = "PERFIL-PRODUCT-DIRECTOR-LF"
CONSUMER = "CONTEXT_PACK"
INPUT = "CHECKOUT_CUOTAS_MEDIO_PAGO Decide prioridad de claridad del checkout usando solo evidencia suministrada."
SNAPSHOT = "a" * 64
CONTRACT = "b" * 64

def router_ready():
    return {"status":"READY","continuation_allowed":True,"governance_receipt":{"decision":"PASS","currentness":"LIVE_CURRENT","snapshot_hash":SNAPSHOT,"contract_snapshot_hash":CONTRACT,"run_id":197,"pantalla_id":21,"screen_code":"CHECKOUT_CUOTAS_MEDIO_PAGO","source_refs":["programacion.input_readiness_runs/197"]}}

def must_fail(label, fn):
    try: fn()
    except GovernanceBindingError: return
    raise SystemExit(f"FAIL {label}: expected GovernanceBindingError")

def main():
    bound=build_bound_governance_receipt(router_ready(),request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)
    validate_bound_governance_receipt(bound,request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)
    build_mutations=[
      ("router_not_ready",lambda:build_bound_governance_receipt({"status":"BLOCKED","continuation_allowed":False},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("receipt_missing",lambda:build_bound_governance_receipt({"status":"READY","continuation_allowed":True},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("decision_not_pass",lambda:build_bound_governance_receipt({**router_ready(),"governance_receipt":{**router_ready()["governance_receipt"],"decision":"BLOCKED"}},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("stale",lambda:build_bound_governance_receipt({**router_ready(),"governance_receipt":{**router_ready()["governance_receipt"],"currentness":"STALE"}},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("bad_snapshot",lambda:build_bound_governance_receipt({**router_ready(),"governance_receipt":{**router_ready()["governance_receipt"],"snapshot_hash":"bad"}},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("bad_contract_snapshot",lambda:build_bound_governance_receipt({**router_ready(),"governance_receipt":{**router_ready()["governance_receipt"],"contract_snapshot_hash":"bad"}},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("missing_screen",lambda:build_bound_governance_receipt({**router_ready(),"governance_receipt":{**router_ready()["governance_receipt"],"screen_code":""}},request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER)),
      ("consumer_not_allowed",lambda:build_bound_governance_receipt(router_ready(),request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=PROFILE))]
    for label,fn in build_mutations: must_fail(label,fn)
    validation_mutations=[("request_id","other"),("profile_code","OTHER"),("governance_consumer","MANUAL"),("input_sha256","c"*64),("decision","BLOCKED"),("currentness","STALE"),("source_snapshot_sha256","d"*64),("contract_snapshot_sha256","e"*64),("governance_receipt_sha256","f"*64),("binding_sha256","0"*64)]
    for key,value in validation_mutations:
        candidate=copy.deepcopy(bound); candidate[key]=value
        must_fail(key,lambda candidate=candidate:validate_bound_governance_receipt(candidate,request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER))
    tampered=copy.deepcopy(bound); tampered["governance_receipt"]["snapshot_hash"]="9"*64
    must_fail("tampered_receipt",lambda:validate_bound_governance_receipt(tampered,request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer=CONSUMER))
    must_fail("wrong_input",lambda:validate_bound_governance_receipt(bound,request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT+" tampered",governance_consumer=CONSUMER))
    must_fail("wrong_expected_consumer",lambda:validate_bound_governance_receipt(bound,request_id=REQUEST_ID,profile_code=PROFILE,input_literal=INPUT,governance_consumer="STORY_CREATOR"))
    print("PRODUCT_DIRECTOR_INPUT_GOVERNANCE_BINDING=PASS")
    print("positive=1 negative=20")
    return 0
if __name__=="__main__": raise SystemExit(main())
