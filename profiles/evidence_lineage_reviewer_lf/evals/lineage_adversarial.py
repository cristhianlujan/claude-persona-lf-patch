#!/usr/bin/env python3
import copy, hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from evaluate_lineage import evaluate

A,B,C=(c*64 for c in "abc")
def base():
    return {
      "claim":"Candidate preserves the governing source at exact revision",
      "candidate_sha":C,
      "candidate_oracle_id":"candidate-builder-v1",
      "artifact_verified":True,
      "sources":[
        {"ref":"authority://governing-source","role":"authority","required":True,"read":True,"declared_sha":A,"observed_sha":A,"current":True,"authority":True,"derived_from_candidate":False,"relevance":"MATERIAL"},
        {"ref":"upstream://validated-output","role":"upstream","required":True,"read":True,"declared_sha":B,"observed_sha":B,"current":True,"authority":False,"derived_from_candidate":False,"relevance":"MATERIAL","validator_status":"PASS","validator_current":True,"receipt_id":"receipt-001","receipt_subject_sha":C,"receipt_replayed":False}
      ],
      "structural_identifiers":[{"canonical":"ACT-0002","observed":"ACT-0002","reconciled":True}],
      "conflicts":[],
      "semantic_assertions":[{"authority_ref":"authority://governing-source","oracle_id":"independent-source-oracle-v2","derived_from_candidate":False,"match":True}]
    }

def case_mutator(fn):
    x=copy.deepcopy(base()); fn(x); return x

cases=[
 ("positive_exact_current","positive",base(),"PASS_EVIDENCE_LINEAGE",None),
 ("sha_head_mismatch","negative",case_mutator(lambda x:x["sources"][0].update({"observed_sha":B})),"RETURN_TO_SOURCE_FOR_READBACK","SOURCE_0_SHA_MISMATCH"),
 ("named_not_read","negative",case_mutator(lambda x:x["sources"][0].update({"read":False})),"RETURN_TO_SOURCE_FOR_READBACK","SOURCE_0_NOT_READ"),
 ("stale_reference","negative",case_mutator(lambda x:x["sources"][1].update({"current":False})),"RETURN_TO_SOURCE_FOR_READBACK","SOURCE_1_STALE"),
 ("self_certified_authority","adversarial",case_mutator(lambda x:x["sources"][0].update({"derived_from_candidate":True})),"BLOCK_PIPELINE","SOURCE_0_SELF_CERTIFIED_AUTHORITY"),
 ("receipt_replay","adversarial",case_mutator(lambda x:x["sources"][1].update({"receipt_replayed":True})),"BLOCK_PIPELINE","RECEIPT_REPLAY"),
 ("receipt_subject_mismatch","negative",case_mutator(lambda x:x["sources"][1].update({"receipt_subject_sha":A})),"BLOCK_PIPELINE","SOURCE_1_RECEIPT_SUBJECT_MISMATCH"),
 ("upstream_invalid_current_validator","crosscheck",case_mutator(lambda x:x["sources"][1].update({"validator_status":"FAIL"})),"BLOCK_PIPELINE","SOURCE_1_UPSTREAM_INVALID"),
 ("structural_identifier_unreconciled","negative",case_mutator(lambda x:x["structural_identifiers"][0].update({"reconciled":False})),"BLOCK_PIPELINE","STRUCTURAL_IDENTIFIER_0_UNRECONCILED"),
 ("contradictory_source","crosscheck",case_mutator(lambda x:x.update({"conflicts":[{"resolved":False}]})),"BLOCK_PIPELINE","SOURCE_CONFLICT_0_UNRESOLVED"),
 ("correlated_oracle","adversarial",case_mutator(lambda x:x["semantic_assertions"][0].update({"oracle_id":"candidate-builder-v1"})),"BLOCK_PIPELINE","ASSERTION_0_CORRELATED_ORACLE"),
 ("trace_complete_semantics_false","holdout",case_mutator(lambda x:x["semantic_assertions"][0].update({"match":False})),"BLOCK_PIPELINE","ASSERTION_0_SEMANTIC_MISMATCH")
]
results=[]; failed=False
for case_id,kind,data,expected_status,expected_code in cases:
    actual=evaluate(data); passed=actual["status"]==expected_status and (expected_code is None or expected_code in actual["blocking_codes"]+actual["readback_codes"])
    failed |= not passed
    results.append({"id":case_id,"kind":kind,"expected_status":expected_status,"expected_code":expected_code,"actual":actual,"passed":passed})
digest=hashlib.sha256(json.dumps(results,sort_keys=True).encode()).hexdigest()
print(json.dumps({"passed":not failed,"case_count":len(results),"results_sha256":digest,"results":results},indent=2))
raise SystemExit(1 if failed else 0)
