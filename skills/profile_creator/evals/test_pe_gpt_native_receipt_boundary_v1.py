#!/usr/bin/env python3
"""Exact-boundary GPT_NATIVE receipt tests. Offline only; no model invocation."""
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
EVALS=ROOT/"skills/profile_creator/evals"
sys.path[:0]=[str(ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"),str(EVALS)]
from profile_runtime_runner import build_runtime_request,_validate_response,RuntimeExecutionBlocked,RESPONSE_TYPE
from profile_execution_contract import canonical_json_sha256
from prepare_profile_evolution_gpt_native_v1 import verify_candidate_receipt

EXPECTED_SHA="f039ef0dea9e5c09a1296cf6a1777a5764bbfdac0cb524b3b51ab2d26644c71f"

class TestOnlyIdentity:
    adapter_id="chatgpt-native-current-context-v1"
    is_test_double=True

def expect_block(code,request,response):
    try: _validate_response(request=request,response=response,adapter=TestOnlyIdentity())
    except RuntimeExecutionBlocked as e:
        assert e.code==code,(code,e.code)
        print("EXPECTED_BLOCK",code)
        return
    raise AssertionError("FAIL_OPEN:"+code)

def main():
    bundle=json.loads((EVALS/"results/pe_gpt_native_12_run_handoff_v1.json").read_text())
    run=next(x for x in bundle["runs"] if x["case_id"]=="HCA-105" and x["arm"]=="D1_STATIC")
    raw_file=json.loads((EVALS/"results/pe_gpt_current_chat_12_task_raw_v1.json").read_text())
    row=next(x for x in raw_file["outputs"] if x["run_id"]==run["run_id"])
    sources=[{"ref":x["ref"],"content":(ROOT/x["ref"]).read_text(encoding="utf-8")}
             for x in run["profile_source_manifest"]]
    contract=run["execution_contract"]
    request=build_runtime_request(
        execution_id=run["run_id"],profile_code=contract["profile_code"],
        profile_slug="systemic_root_cause_repair_lf",profile_sources=sources,
        input_literal=run["input_literal"],
        obligation_manifest=run["scoped_semantic_obligation_manifest"])
    request.update(executor_mode="GPT_NATIVE",execution_contract_sha256=contract["contract_sha256"],
                   execution_contract=contract)
    request["request_sha256"]=canonical_json_sha256({k:v for k,v in request.items() if k!="request_sha256"})
    assert request["request_sha256"]==EXPECTED_SHA
    print("EXACT_REQUEST_SHA",EXPECTED_SHA)
    raw=row["raw_output"]
    expect_block("RUNTIME_RESPONSE_TYPE_INVALID",request,row)
    expect_block("RUNTIME_ATTESTATION_MISSING",request,
        {"response_type":RESPONSE_TYPE,"raw_output":raw})
    # All attestation fields below are fabricated negative-test inputs, never proof.
    att={
        "provider":"OPENAI_CHATGPT_NATIVE","model_id":"GPT-6","run_id":"TEST_ONLY_UNVERIFIED",
        "attested_at":"2026-10-12T02:00:00-05:00","adapter_id":TestOnlyIdentity.adapter_id,
        "executor_mode":"GPT_NATIVE","request_sha256":request["request_sha256"],
        "profile_source_sha256":request["profile_source_sha256"],
        "input_sha256":request["input_sha256"],"operation_code":request["operation_code"],
        "profile_code":request["profile_code"],"profile_slug":request["profile_slug"]}
    expect_block("RUNTIME_ATTESTATION_REQUEST_SHA256_MISMATCH",request,
        {"response_type":RESPONSE_TYPE,"raw_output":raw,
         "runtime_attestation":dict(att,request_sha256="0"*64)})
    expect_block("RUNTIME_RAW_OUTPUT_EMPTY",request,
        {"response_type":RESPONSE_TYPE,"raw_output":{},"runtime_attestation":att})
    _validate_response(request=request,response={"response_type":RESPONSE_TYPE,
        "raw_output":raw,"runtime_attestation":att},adapter=TestOnlyIdentity())
    print("STRUCTURAL_PASS_ONLY_UNVERIFIED_TEST_INPUT")
    assert "GPT_NATIVE_RECEIPT_MISSING" in verify_candidate_receipt(bundle,None,raw)
    assert "INDEPENDENT_NATIVE_ATTESTATION_VERIFIER_REQUIRED" in verify_candidate_receipt(
        bundle,{"execution_id":run["run_id"],"runtime_attestation":{"executor_mode":"GPT_NATIVE"}},raw)
    print("RECEIPT_AND_INDEPENDENT_VERIFIER_REQUIRED")
    print("NO_MODEL_CALL_NO_AUTHORITY_WRITE_NO_CUTOVER")
if __name__=="__main__": main()
