#!/usr/bin/env python3
"""GPT-native Profile Evolution handoff: fail-closed, no synthetic model calls."""
from __future__ import annotations
from copy import deepcopy
import hashlib
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"skills/profile_creator/evals"))
from prepare_profile_evolution_gpt_native_v1 import (
    package,verify_candidate_receipt,load,canonical_json_sha256,
    HandoffError,ARMS,PROFILE
)
from profile_execution_contract import validate_execution_contract
from semantic_obligation_manifest import validate_obligation_manifest

def check():
    b=package()
    assert b["runtime_mode"]=="GPT_NATIVE"
    assert b["semantic_review_mode"]=="INDEPENDENT_CHAT_CONTEXT"
    assert b["quality_pack_visual_rubric_not_causal_oracle"] is True
    assert "profile_evolution_causal_semantic_review_v1.md" in b["causal_semantic_rubric_ref"]
    assert b["resolver"]=="GPT_RUNTIME_WITH_SUPABASE_CONTEXT"
    assert b["profile_execution_operation"]=="EJECUCION_PERFIL_LF"
    assert b["profile_execution_step"]=="execute_profile"
    assert b["router"]=="ACT-0001"
    assert b["case_count"]==4 and b["run_count"]==12
    assert b["gpt_model_invocations"]==0
    assert b["producer_status"]=="NOT_EXECUTED"
    assert b["independent_review_invocations"]==0
    assert b["production_activation"] is False
    assert b["cutover_eligible"] is False
    assert set(x["arm"] for x in b["runs"])==set(ARMS)
    seen=set()
    for run in b["runs"]:
        assert run["run_id"] not in seen
        seen.add(run["run_id"])
        contract=run["execution_contract"]
        assert validate_execution_contract(contract,expected_executor_mode="GPT_NATIVE")==[]
        assert contract["contract_sha256"]==canonical_json_sha256(
            {k:v for k,v in contract.items() if k!="contract_sha256"})
        assert contract["run_id"]==run["run_id"]
        assert contract["executor_mode"]=="GPT_NATIVE"
        assert "PROFILE_AUTHORITY_WRITE" in contract["forbidden_actions"]
        assert "PAID_MODEL_API" in contract["forbidden_actions"]
        assert run["input_sha256"]==hashlib.sha256(run["input_literal"].encode("utf-8")).hexdigest()
        assert run["profile_source_manifest"][0]["ref"]==PROFILE
        manifest=run["scoped_semantic_obligation_manifest"]
        assert run["semantic_obligation_scope"]=="FIVE_TEST_CASE_OBLIGATIONS_NOT_COMPLETE_EXPERTISE"
        assert canonical_json_sha256(manifest)==run["scoped_semantic_obligation_manifest_sha256"]
        assert isinstance(contract["context_fingerprint"],str) and len(contract["context_fingerprint"])==64
        validate_obligation_manifest(manifest,expected_execution_id=run["run_id"],
                                    expected_profile_code=contract["profile_code"],
                                    expected_profile_source_sha256=run["profile_source_sha256"],
                                    expected_input_sha256=run["input_sha256"])
        assert len(manifest["obligations"])==5
        assert run["producer_receipt"] is None
        assert run["producer_status"]=="PENDING_GPT_NATIVE_EXECUTION"
        assert run["review_status"]=="PENDING_INDEPENDENT_CHAT_CONTEXT"
        payload=json.loads(run["input_literal"])
        if run["arm"]=="D1_STATIC":
            assert "selector_result" not in payload and "tool_result" not in payload
        if run["arm"]=="D2_SELECTOR_ONLY":
            assert payload["selector_result"]["method_executed"] is False
            assert payload["selector_result"]["execution_authorized"] is False
            assert "tool_result" not in payload
        if run["arm"]=="D3_TYPED_METHOD":
            assert payload["tool_result"]["source_attestation"]=="TEST_NON_AUTHORITY"
            assert payload["tool_result"]["governed_method_admission"] is False
            assert payload["tool_result"]["causality_proven"] is False
    assert len(seen)==12
    # A self-described "native" result is never equivalent to verified runtime.
    forged={"execution_id":b["runs"][0]["run_id"],
            "executor_mode":"GPT_NATIVE","attestation_verified":True}
    errors=verify_candidate_receipt(b,forged)
    assert "INDEPENDENT_NATIVE_ATTESTATION_VERIFIER_REQUIRED" in errors
    assert "RUNTIME_ATTESTATION_MISSING" in errors
    errors=verify_candidate_receipt(b,forged,{},independent_attestation_verifier=lambda r,o:False)
    assert "INDEPENDENT_NATIVE_ATTESTATION_NOT_VERIFIED" in errors
    errors=verify_candidate_receipt(b,dict(forged,execution_id="UNKNOWN"))
    assert "UNKNOWN_EXECUTION_ID" in errors
    assert "GPT_NATIVE_RECEIPT_MISSING" in verify_candidate_receipt(b,None)
    # Mutation must not silently carry a different selector/case into the model.
    import prepare_profile_evolution_gpt_native_v1 as module
    original=module.load
    def tampered(path):
        x=original(path)
        if path==module.SELECTOR:
            x=deepcopy(x)
            x["receipts"][0]["source_evidence_refs"]=["fixture://tampered"]
        return x
    try:
        module.load=tampered
        try:
            module.package()
        except HandoffError as exc:
            assert "SELECTOR_PROVENANCE_MISMATCH" in str(exc)
        else:
            raise AssertionError("TAMPER_NOT_DETECTED")
    finally:
        module.load=original
    assert b==package()
    print(json.dumps({"result":"PASS","prepared_runs":12,"native_invocations":0,
       "fake_receipt_blocked":True,"selector_tamper_blocked":True,
       "review_context_created":False,"production":False},sort_keys=True))
if __name__=="__main__":check()
