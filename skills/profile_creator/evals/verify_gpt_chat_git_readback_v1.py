#!/usr/bin/env python3
"""Bind ChatGPT-current-chat calibration to immutable Git source bytes.

Readback is NOT a model provider attestation, an independently isolated GPT
run, or external semantic assurance. Never emit admitted execution receipts.
"""
from __future__ import annotations
import hashlib,json,subprocess,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"))
from profile_execution_contract import validate_execution_contract,canonical_json_sha256
from semantic_obligation_manifest import validate_obligation_manifest

REPO_PATH="skills/profile_creator/evals/results/pe_gpt_current_chat_12_task_raw_v1.json"
RAW=ROOT/REPO_PATH
RAW_MATERIALIZATION_COMMIT="7119a0ec926e7afbfe3ca72612a2e6d35ed146db"
HANDOFF=ROOT/"skills/profile_creator/evals/results/pe_gpt_native_12_run_handoff_v1.json"
SCORE=ROOT/"skills/profile_creator/evals/results/pe_gpt_current_chat_12_task_score_v1.json"
OUT=ROOT/"skills/profile_creator/evals/results/pe_gpt_current_chat_source_readback_v1.json"

def h_bytes(x:bytes)->str:
    return hashlib.sha256(x).hexdigest()

def verify()->dict:
    git_raw=subprocess.run(["git","-C",str(ROOT),"show",RAW_MATERIALIZATION_COMMIT+":"+REPO_PATH],
                           check=True,capture_output=True).stdout
    assert git_raw==RAW.read_bytes(),"RAW_DIFFERS_FROM_MATERIALIZATION_COMMIT"
    raw=json.loads(git_raw)
    bundle=json.loads(HANDOFF.read_text())
    score=json.loads(SCORE.read_text())
    assert raw["batch_scope"]=="SINGLE_CURRENT_GPT_CONVERSATION_NOT_TWELVE_SEPARATE_PROVIDER_RUNS"
    assert raw["independent_provider_attestation"] is False
    assert raw["independent_semantic_review"] is False
    assert len(raw["outputs"])==12
    assert bundle["run_count"]==len(bundle["runs"])==12
    assert bundle["runtime_mode"]=="GPT_NATIVE"
    assert bundle["gpt_model_invocations"]==0 # prepared bundle's historical state
    assert score["native_execution_receipts_verified"]==0
    assert score["blind_powered_benchmark"] is False
    runs={r["run_id"]:r for r in bundle["runs"]}
    proof=[]
    for o in raw["outputs"]:
        assert o["run_id"] in runs
        r=runs[o["run_id"]]
        assert o["input_sha256"]==r["input_sha256"]
        assert o["contract_sha256"]==r["execution_contract"]["contract_sha256"]
        assert validate_execution_contract(r["execution_contract"],expected_executor_mode="GPT_NATIVE")==[]
        assert h_bytes(r["input_literal"].encode())==r["input_sha256"]
        manifest=validate_obligation_manifest(
          r["scoped_semantic_obligation_manifest"],
          expected_execution_id=r["run_id"],
          expected_profile_code=r["execution_contract"]["profile_code"],
          expected_profile_source_sha256=r["profile_source_sha256"],
          expected_input_sha256=r["input_sha256"])
        assert canonical_json_sha256(manifest)==r["scoped_semantic_obligation_manifest_sha256"]
        assert o["raw_output"]["case_id"]==r["case_id"]
        assert o["raw_output"]["causality_proven"] is False
        proof.append({"run_id":r["run_id"],"arm":r["arm"],
            "profile_source_sha256":r["profile_source_sha256"],
            "input_sha256":r["input_sha256"],
            "contract_sha256":r["execution_contract"]["contract_sha256"],
            "obligation_manifest_sha256":r["scoped_semantic_obligation_manifest_sha256"],
            "response_content_sha256":canonical_json_sha256(o["raw_output"]),
            "git_materialization_commit":RAW_MATERIALIZATION_COMMIT,
            "source_readback":"BYTES_MATCH_GIT",
            "provider_runtime_attestation":"NOT_AVAILABLE",
            "semantic_review":"NOT_EXECUTED"})
    assert len({r["run_id"] for r in proof})==12
    return {
     "schema":"PE_GPT_CHAT_GIT_READBACK_V1",
     "status":"GIT_SOURCE_BINDING_PASS_NOT_RUNTIME_ATTESTED",
     "raw_git_commit":RAW_MATERIALIZATION_COMMIT,
     "raw_sha256":h_bytes(git_raw),
     "handoff_sha256":h_bytes(HANDOFF.read_bytes()),
     "score_sha256":h_bytes(SCORE.read_bytes()),
     "source_bound_rows":len(proof),
     "source_git_readback":"PASS",
     "model_output_provenance":"CURRENT_GPT_CHAT_SINGLE_CONTEXT",
     "independent_gpt_model_runs":0,
     "independent_provider_attestations":0,
     "independent_semantic_reviews":0,
     "expertise_uplift_proven":False,
     "authority_activated":False,
     "cutover_eligible":False,
     "bindings":proof}

def main():
    doc=verify()
    data=json.dumps(doc,ensure_ascii=False,sort_keys=True,indent=2)+"\n"
    if OUT.exists():
        assert OUT.read_text()==data,"FROZEN_RESULT_MISMATCH"
    else:
        OUT.write_text(data)
    print(json.dumps({"status":doc["status"],"bound":doc["source_bound_rows"],
      "raw_sha256":doc["raw_sha256"],"readback_file_sha256":h_bytes(OUT.read_bytes()),
      "independent_provider_attestations":0},sort_keys=True))

if __name__=="__main__":main()
