#!/usr/bin/env python3
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_method_rationale_gate_v1 import verify_rationale
RAW=ROOT/"pe_causal_compact_calibration_raw_v1.json"
j=json.loads(RAW.read_text())
assert len(j["answer"]["answers"])==2
checks=0
for answer in j["answer"]["answers"]:
 r=verify_rationale(answer,verify_source=lambda _:True,verify_claim=lambda *_:True)
 assert r["status"]=="BLOCKED" and r["reason"]=="CLAIM_LEVEL_EVIDENCE_REQUIRED"
 checks+=1
supported={"causality_proven":False,"reason_claims":[{"type":"OBSERVATION",
 "text":"The frozen readback confirms the worker receipt is present",
 "evidence_refs":["receipt://verified-01"]}]}
r=verify_rationale(supported,verify_source=lambda r:r=="receipt://verified-01",
                   verify_claim=lambda claim,answer:claim["text"].startswith("The frozen readback"))
assert r["status"]=="TEST_ONLY_GROUNDED_RATIONALE" and not r["publication_authorized"]
checks+=1
tampered={"causality_proven":False,"reason_claims":[{"type":"INFERENCE","text":"The replica is stale",
 "evidence_refs":["fixture://unverified-mirror"]}]}
r=verify_rationale(tampered,verify_source=lambda _:False,verify_claim=lambda *_:True)
assert r["status"]=="BLOCKED" and r["reason"]=="CLAIM_USES_UNVERIFIED_SOURCE"
checks+=1
r=verify_rationale(supported,verify_source=lambda _:True,verify_claim=lambda *_:False)
assert r["status"]=="BLOCKED" and r["reason"]=="INDEPENDENT_SEMANTIC_JUDGE_DID_NOT_VERIFY"
checks+=1
r=verify_rationale(supported,verify_source=lambda _:True,verify_claim=None)
assert r["status"]=="BLOCKED" and r["reason"]=="INDEPENDENT_SOURCE_AND_SEMANTIC_VERIFIERS_REQUIRED"
checks+=1
print("PASS_PROFILE_METHOD_RATIONALE_GATE_V1 checks="+str(checks)+" compact_model_explanations_blocked=2 no_production=true")
