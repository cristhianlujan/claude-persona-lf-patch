#!/usr/bin/env python3
"""Negative tests + explicitly synthetic positive of GPT review-handoff transport."""
from __future__ import annotations
import copy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"skills/profile_creator/evals"))
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"))
from prepare_profile_evolution_gpt_native_v1 import package
from prepare_profile_evolution_gpt_review_v1 import prepare_review_handoff
from validate_profile_execution import build_receipt

def main():
    b=package()
    selected=b["runs"][8] # synthetic D3 fixture only
    run=selected["run_id"]
    raw={"case_id":selected["case_id"],"decision":"COLLECT_MORE_EVIDENCE",
         "falsified":["H1"],"causality_proven":False,
         "reason_claim_ids":["OBS:OWNER_EXISTS"],
         "rationale":"SYNTHETIC-TEST-FIXTURE-NOT-A-MODEL-ANSWER"}
    attestation={"provider":"TEST_DOUBLE_NO_NATIVE_EXECUTION",
      "model_id":"NONEXECUTABLE_FIXTURE","run_id":run,
      "attested_at":"2026-10-09T00:00:00Z",
      "attestation_verifier":"SYNTHETIC_VALIDATION_ONLY",
      "attestation_evidence_sha256":"a"*64,
      "verified_request_sha256":"b"*64,
      "verified_response_sha256":"c"*64,
      "executor_mode":"GPT_NATIVE"}
    receipt=build_receipt(execution_id=run,
       profile_code=selected["execution_contract"]["profile_code"],
       profile_slug="systemic_root_cause_repair_lf",
       profile_source_refs=[x["ref"] for x in selected["profile_source_manifest"]],
       profile_source_sha256=selected["profile_source_sha256"],
       input_literal=selected["input_literal"],raw_output=raw,
       runtime_attestation=attestation)
    # Production without a genuine verifier must NEVER qualify.
    blocked=prepare_review_handoff(b,receipt,raw,independent_attestation_verifier=None)
    assert blocked["status"]=="BLOCKED"
    assert blocked["blocking_codes"]==["REAL_NATIVE_ATTESTATION_REQUIRED"]
    blocked=prepare_review_handoff(b,receipt,raw,independent_attestation_verifier=lambda *_:False)
    assert "INDEPENDENT_NATIVE_ATTESTATION_NOT_VERIFIED" in blocked["blocking_codes"]
    blocked=prepare_review_handoff(b,receipt,dict(raw,case_id="WRONG"),independent_attestation_verifier=lambda *_:False)
    assert blocked["status"]=="BLOCKED"
    # Explicitly synthetic positive tests only the transport's domain/case
    # blinding and binding. It is NOT a real GPT native attestation or review.
    prepared=prepare_review_handoff(b,receipt,raw,independent_attestation_verifier=lambda *_:True)
    assert prepared["status"]=="READY_FOR_EXTERNAL_INDEPENDENT_REVIEW_NOT_EXECUTED",prepared
    view=prepared["review_request"]
    assert view["hidden_oracle_not_supplied"] is True
    assert view["quality_pack_visual_score_is_not_causal_oracle"] is True
    assert "causal_semantic_review_v1.md" in view["domain_rubric_ref"]
    assert view["expected_verdict"] is None
    assert view["review_status"]=="PENDING_ACTUAL_INDEPENDENT_GPT_REVIEW"
    as_text=json.dumps(view,sort_keys=True)
    assert '"arm"' not in as_text
    assert '"tool_result"' not in as_text
    assert '"selector_result"' not in as_text
    assert "D3_TYPED_METHOD" not in as_text
    assert "method_decision" not in as_text
    assert "candidate_method" not in as_text
    assert prepared["semantic_pass"] is False
    assert prepared["review_completed"] is False
    assert prepared["cutover_eligible"] is False
    mutated=copy.deepcopy(receipt)
    mutated["raw_output_sha256"]="0"*64
    blocked=prepare_review_handoff(b,mutated,raw,independent_attestation_verifier=lambda *_:True)
    assert blocked["status"]=="BLOCKED" and "RAW_OUTPUT_SHA256_MISMATCH" in blocked["blocking_codes"]
    overclaim=dict(raw,causality_proven=True)
    r2=build_receipt(execution_id=run,profile_code=selected["execution_contract"]["profile_code"],
       profile_slug="systemic_root_cause_repair_lf",
       profile_source_refs=[x["ref"] for x in selected["profile_source_manifest"]],
       profile_source_sha256=selected["profile_source_sha256"],
       input_literal=selected["input_literal"],raw_output=overclaim,
       runtime_attestation=attestation)
    blocked=prepare_review_handoff(b,r2,overclaim,independent_attestation_verifier=lambda *_:True)
    assert blocked["status"]=="BLOCKED" and blocked["blocking_codes"]==["PRODUCER_CAUSALITY_OVERCLAIM"]
    print(json.dumps({"status":"PASS_SYNTHETIC_TRANSPORT_TEST_ONLY",
         "assertions":"no_native_receipt_blocked; verifier_missing_blocked; tampered_receipt_blocked; causal_overclaim_blocked; blinded_view_no_arm; pending_review_only",
         "actual_gpt_native_calls":0,
         "independent_review_calls":0,
         "expert_admission":False},sort_keys=True))
if __name__=="__main__":main()
