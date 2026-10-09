#!/usr/bin/env python3
"""PE-C1: REAL CAUSAL_EFFECT_LINEAGE provider invoked under CAUSAL_ANALYSIS.

Scope: frozen R3 receipts / read-only / explicit test-local permission.
This tests a *causal-continuity subskill*, NOT generic root-cause expertise.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "sandbox/lf_contract_gate_test/transversal_assets"
sys.path[:0] = [str(ASSETS/"capability_selector"),
                str(ASSETS/"causal_effect_lineage")]
from capability_selector_v3 import compose_capabilities_v3
from method_execution_bridge_v1 import execute_method_selection, _sha
from causal_effect_lineage_v1 import evaluate_lineage

RAW = ROOT/"pexp_r3_producer_raw.json"
REG = ASSETS/"method_pack_registry/method_pack_registry_v2.json"
FROZEN_RAW_SHA = "8f891da0aa4a3056a60924ce56458e2dbca2cfb040599e708224893c1d5b83a2"
CASE_ID = "PEXR-001"
SOURCE_CODE = "CAUSAL_EFFECT_LINEAGE"
SOURCE_VERSION = "1.0.1"

def verified(value):
    return {"value": value, "verification_state": "VERIFIED",
            "evidence_refs": ["benchmark://PEXP-R3/frozen-raw"]}

def freeze_readback():
    data = RAW.read_bytes()
    assert hashlib.sha256(data).hexdigest() == FROZEN_RAW_SHA
    raw = json.loads(data)
    assert raw["raw_frozen"] is True
    a = next(x for x in raw["batches"] if x["profile_slug"]=="systemic_root_cause_repair_lf"
             and x["batch_index"]==1 and x["arm"]=="A_ORIGINAL")
    b = next(x for x in raw["batches"] if x["profile_slug"]=="systemic_root_cause_repair_lf"
             and x["batch_index"]==1 and x["arm"]=="B_UPDATER_V01")
    child_a = next(x for x in raw["cases"] if x["case_id"] == CASE_ID)["arms"]["A_ORIGINAL"]["case_execution_receipt"]
    child_b = next(x for x in raw["cases"] if x["case_id"] == CASE_ID)["arms"]["B_UPDATER_V01"]["case_execution_receipt"]
    assert a["runtime_attestation_verification"]["verified"] is True
    assert b["runtime_attestation_verification"]["verified"] is True
    p = a["profile_execution_receipt"]
    for receipt in (p, child_a, child_b, b["profile_execution_receipt"]):
        inner = {k:v for k,v in receipt.items() if k != "receipt_sha256"}
        assert _sha(inner) == receipt["receipt_sha256"]
    assert child_a["parent_profile_execution_receipt_sha256"]==p["receipt_sha256"]
    assert child_b["parent_profile_execution_receipt_sha256"]==b["profile_execution_receipt"]["receipt_sha256"]
    assert child_b["parent_profile_execution_receipt_sha256"]!=p["receipt_sha256"]
    return p, child_a, child_b

def adapt(parent, child):
    pid = {"scope":"benchmark-run","opaque_id":parent["execution_id"]}
    corr = {"scope":"benchmark-case","opaque_id":child["case_id"]}
    producer={"receipt_id":"parent-01","receipt_sha256":parent["receipt_sha256"],
        "verification_state":"VERIFIED",
        "receipt_payload":{"causal_role":"PRODUCER","parent_identity":pid,
                           "correlation_identity":corr,"currentness":"CURRENT"}}
    receiver={"receipt_id":"child-01","receipt_sha256":child["receipt_sha256"],
        "verification_state":"VERIFIED",
        "receipt_payload":{"causal_role":"RECEIVER_EFFECT","parent_identity":pid,
                           "correlation_identity":corr,"currentness":"CURRENT",
                           "producer_receipt_sha256":child["parent_profile_execution_receipt_sha256"],
                           "effect_ref":"case-"+child["case_id"]}}
    return {"parent_identity":pid,"correlation_identity":corr,
        "provenance":{"boundary":"SYNC","producer":"model-runtime",
                      "receiver":"case-receipt","authority_ref":"frozen-R3-raw"},
        "currentness":{"producer":"CURRENT","receiver":"CURRENT",
                       "correlation":"CURRENT"},
        "producer_receipt":producer,"receiver_effect_receipt":receiver,
        "receiver_readback":{"observed":True,"currentness":"CURRENT",
            "effect_ref":"case-"+child["case_id"],
            "receiver_receipt_sha256":child["receipt_sha256"]}}

def main():
    parent, child_ok, child_other = freeze_readback()
    registry=json.loads(REG.read_text())
    assert registry["execution_permission"] is False
    # A non-authority fixture grants *only* isolated test execution.
    local_registry=copy.deepcopy(registry)
    local_registry["execution_permission"]=True
    selection=compose_capabilities_v3(
        {"causal_requirement":"HIGH","budget":{"max_method_cost_points":2}},
        [], {"fallback_capabilities":[]}, local_registry,
        {"evidence_sufficiency":verified("SUFFICIENT")})
    selected=[m["method_id"] for m in selection["selected_methods"]]
    assert selected==["CAUSAL_ANALYSIS"],selected
    captured=[]
    def actual_provider_handler(data):
        # This is the ACTUAL published domain-neutral implementation, not a fake lambda.
        outcome=evaluate_lineage(data["lineage"])
        captured.append(outcome)
        return {"verification_state":"VERIFIED","capability":SOURCE_CODE,
                "source_version":SOURCE_VERSION,"lineage":outcome}
    permission={"scope":"TEST_NON_AUTHORITY","execution_id":"PE-C1-R3-LINEAGE-001",
                "allowed_method_ids":["CAUSAL_ANALYSIS"],
                "receipt_ref":"fixture://read-only-frozen-profile-evidence"}
    def verifier(mid, data, result):
        if mid!="CAUSAL_ANALYSIS" or result["capability"]!=SOURCE_CODE:return False
        outcome=result["lineage"]
        if outcome["execution_permission"] is not False:return False
        return outcome==evaluate_lineage(data["lineage"])
    outputs=[]
    for label,child in (("MATCHED_ACTUAL_CHILD",child_ok),
                        ("CROSS_EXECUTION_ACTUAL_CHILD",child_other)):
        payload={"lineage":adapt(parent,child)}
        result=execute_method_selection(
            selection,local_registry,
            {"CAUSAL_ANALYSIS":{"handler":actual_provider_handler,"scope":"TEST_NON_AUTHORITY",
              "executor_id":"CAUSAL_EFFECT_LINEAGE_REAL_PROVIDER_TEST_BINDING",
              "source_revision":"CAUSAL_EFFECT_LINEAGE@"+SOURCE_VERSION,
              "execution_contract_ref":"contract://CAUSAL_EFFECT_LINEAGE_V1"}},
            {"CAUSAL_ANALYSIS":payload},
            execution_id=permission["execution_id"],
            evidence_refs=["benchmark://PEXP-R3/frozen-raw","benchmark://PEXP-R3/"+CASE_ID],
            scope="TEST_NON_AUTHORITY",permission_receipt=permission,
            verify_permission=lambda p:p==permission,
            verify_selection=lambda s:_sha(s)==_sha(selection),
            verify_result=verifier,
            result_verifier_id="LINEAGE-READBACK-INDEPENDENT-RECOMPUTE")
        outcome=captured[-1]
        assert result["status"]=="EXECUTED_TEST_ONLY",result
        assert result["actual_method_invocations"]==1
        assert not result["production_authorized"]
        if label=="MATCHED_ACTUAL_CHILD":
            assert outcome["state"]=="LINKED" and outcome["causal_edge_digest"]
        else:
            assert outcome["state"]=="UNLINKED"
            assert outcome["reasons"]==["RECEIVER_DOES_NOT_CROSSLINK_PRODUCER"]
        outputs.append({"case":label,"provider":SOURCE_CODE,"state":outcome["state"],
            "reasons":outcome["reasons"],
            "receipt_sha256":result["invocations"][0]["receipt_sha256"],
            "observed_wall_ms":result["invocations"][0]["observed_wall_ms"]})
    # Original registry must continue refusing invocations (no permission bypass).
    denied=execute_method_selection(
        selection,registry,{}, {},execution_id=permission["execution_id"],
        evidence_refs=["benchmark://PEXP-R3/frozen-raw"],scope="TEST_NON_AUTHORITY",
        permission_receipt=permission,verify_permission=lambda p:p==permission,
        verify_selection=lambda s:True,verify_result=verifier,
        result_verifier_id="LINEAGE-READBACK-INDEPENDENT-RECOMPUTE")
    assert denied["blocking_codes"]==["REGISTRY_EXECUTION_PERMISSION_NOT_GRANTED"]
    result={"schema":"PE_CAUSAL_PROVIDER_LIVENESS_V1",
            "status":"SUBCAPABILITY_E2E_PASS_NOT_FULL_CAUSAL_ANALYSIS",
            "producer_raw_sha256":FROZEN_RAW_SHA,"source_capability":SOURCE_CODE,
            "source_version":SOURCE_VERSION,"method_id":"CAUSAL_ANALYSIS",
            "test_scope":"TEST_NON_AUTHORITY",
            "actual_provider_calls":len(captured),"tests":outputs,
            "governed_registry_permission":False,
            "production_invocations":0,"cutover_eligible":False}
    out=ROOT/"pe_causal_provider_liveness_raw_v1.json"
    assert not out.exists(),"OUTPUT_ALREADY_EXISTS"
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
    print(json.dumps(result,sort_keys=True))
if __name__=="__main__":
    main()
