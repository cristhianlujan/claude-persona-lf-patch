#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
def load(name): return json.loads((HERE/name).read_text(encoding="utf-8"))
def evaluate():
    live=load("c05_live_schema_readback_v1.json"); c=load("c05_dynamic_reliability_contract_v1.json"); blockers=[]
    if live["lf_operation_execution"]["required_c05_columns_present"] is not True: blockers.append("LIVE_TYPED_IDEMPOTENCY_LEASE_CARRIER_ABSENT")
    if live["operation_registry_readback"]["rows_found"] != 0: blockers.append("UNEXPECTED_OPERATION_PRE_REGISTRATION")
    if c["status"] != "PREPARED_NOT_EXECUTED": blockers.append("CONTRACT_STATE_INVALID")
    expected=(blockers==["LIVE_TYPED_IDEMPOTENCY_LEASE_CARRIER_ABSENT"])
    return {"interface":"S30_C05_PREPARATION_GATE_V1","status":"PASS_PREPARATION" if expected else "BLOCKED","structural_preparation_ready":expected,"dynamic_execution_allowed":False,"activation_allowed":False,"expected_dynamic_blockers":blockers,"claim_ceiling":c["claim_ceiling"],"model_calls":0}
if __name__=="__main__": print(json.dumps(evaluate(),sort_keys=True))
