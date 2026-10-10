#!/usr/bin/env python3
"""Replay an actually observed, read-only Supabase conversational pilot.

The tool answers were obtained live in the operator chat and frozen in Git.
This proves policy routing against those snapshots, not an independently
attested GPT model execution or a real user incident.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"))
from profile_conversational_context_v1 import route_context_turn

INPUT=ROOT/"skills/profile_creator/evals/results/pe_conversational_live_load_smoke_input_v1.json"
OUTPUT=ROOT/"skills/profile_creator/evals/results/pe_conversational_live_load_smoke_result_v1.json"

def replay() -> dict:
    evidence=json.loads(INPUT.read_text())
    assert evidence["schema"]=="PROFILE_CONVERSATIONAL_LIVE_SMOKE_INPUT_V1"
    assert evidence["readback"]["table_exists"] is True
    assert evidence["readback"]["loads_total"]==0
    assert evidence["readback"]["processed"]==0
    assert evidence["planner_result_before_readback"]["state"]=="CONTINUE"
    assert evidence["planner_result_after_readback"]["state"]=="STOP"
    request=evidence["planner_request"]
    task={
      "schema":"PROFILE_CONVERSATIONAL_CONTEXT_V1",
      "request_text":evidence["initial_message"],
      "requested_depth":"DIAGNOSE",
      "consumer_ref":request["consumer_ref"],
      "requirements":[
        {"reason":"load_identity","min_source_level":"USER_CONTEXT"},
        {"reason":"processing_evidence","min_source_level":"TRUSTED_READBACK"}],
      "facts":[],
      "acquisitions":request["candidates"],
      "questions":evidence["questions"],
      "asked_question_ids":[],
      "question_budget":1}
    first=route_context_turn(task)
    assert first["action"]=="RESOLVE_EVIDENCE_PLAN",first
    assert first["acquisition_request"]==request,first
    second=route_context_turn(task,evidence["planner_result_before_readback"])
    assert second["action"]=="RETRIEVE",second
    assert second["next_evidence"]["candidate_ref"]=="LOAD_BATCH_READBACK"
    assert second["execution_performed"] is False
    # The actual read-only count=0 returned no load-specific fact.
    # A lookup that returned nothing cannot be encoded as verified load status.
    task["acquisitions"]=[{**a,"available":False} for a in task["acquisitions"]]
    assert task["facts"]==[]
    third=route_context_turn(task,evidence["planner_result_after_readback"])
    assert third["action"]=="ASK_USER",third
    assert third["question"]["id"]=="load_source"
    assert third["context_sufficient"] is False
    assert third["write_authorized"] is False
    assert third["production_activation"] is False
    # Never duplicate the same question when user has not replied.
    task["asked_question_ids"]=["load_source"]
    fourth=route_context_turn(task,evidence["planner_result_after_readback"])
    assert fourth["action"]=="LIMITED_RESPONSE",fourth
    assert fourth["disclose_limits"] is True
    return {
      "schema":"PE_CONVERSATIONAL_LIVE_READBACK_REPLAY_V1",
      "status":"PASS_REAL_READONLY_TOOL_SNAPSHOT_REPLAY",
      "case_id":evidence["case_id"],
      "initial_user_request":evidence["initial_message"],
      "tool_provenance":"LIVE_SUPABASE_READONLY_RESPONSES_FROZEN_IN_GIT_NOT_PROVIDER_SIGNED",
      "source_claim_scope":evidence["readback"]["claim_ceiling"],
      "stage_actions":[first["action"],second["action"],third["action"],fourth["action"]],
      "source_checked":evidence["readback"]["source_ref"],
      "loads_found":0,
      "next_question":third["question"]["text"],
      "resolved_incident":False,
      "real_user_reply":False,
      "independent_gpt_runtime_attestation":False,
      "independent_semantic_review":False,
      "expert_uplift_proven":False,
      "production_activation":False,
      "cutover_eligible":False}
def main():
    result=replay()
    encoded=json.dumps(result,sort_keys=True,indent=2,ensure_ascii=False)+"\n"
    if OUTPUT.is_file():
        assert OUTPUT.read_text()==encoded,"FROZEN_RESULT_DRIFT"
    else:
        OUTPUT.write_text(encoded)
    print(json.dumps(result,sort_keys=True,ensure_ascii=False))
if __name__=="__main__":
    main()
