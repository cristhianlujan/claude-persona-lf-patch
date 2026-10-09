#!/usr/bin/env python3
"""Two contract-bound REMOTE_API pilot model executions, no admission claims.

Pilot arms share D candidate profile source. Tool arm gets the prior
actual CAUSAL_EFFECT_LINEAGE receipt. Independent score remains separate.
"""
from __future__ import annotations
import dataclasses, hashlib, json, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path[:0]=[str(ROOT/"services/profile_runtime_api"),str(ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"),str(ROOT/"skills/profile_creator/evals")]
from run_profile_expert_behavior_remote_v3 import section_projection,git_show,arm_sources
from profile_execution_contract import build_execution_contract,canonical_json_sha256
from contract_bound_profile_runtime import execute_contract_bound_profile_runtime
from profile_runtime_api.llama import LlamaHTTPClient,PersistentLlamaServerAdapter,PersistentLlamaServerVerifier
from profile_runtime_api.settings import Settings
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_runner import build_runtime_request
from profile_runtime_api.hashing import sha256_text

CAMPAIGN="PE-CAUSAL-PILOT-20261009-001"
TASK="causal-continuity-cross-execution"
OUTPUT=ROOT/"pe_causal_pilot_producer_raw_v1.json"
PROJECTION=ROOT/"skills/profile_creator/evals/profile_expert_benchmark_source_projection_v1.json"
CAMPAIGN_SOURCE=ROOT/"skills/profile_creator/evals/profile_expert_behavior_campaign_remote_v3.json"
LIVENESS=ROOT/"pe_causal_provider_liveness_raw_v1.json"
SCHEMA={"type":"object","properties":{
    "causal_state":{"type":"string","enum":["LINKED","UNLINKED","UNKNOWN"]},
    "decision":{"type":"string","enum":["REJECT_AND_RECONCILE","APPROVE_TRANSITION","RETRY_WITHOUT_PROOF"]},
    "reason":{"type":"string","maxLength":180}},
    "required":["causal_state","decision","reason"],"additionalProperties":False}

def load_context():
    c=json.loads(CAMPAIGN_SOURCE.read_text())
    meta=next(x for x in json.loads(PROJECTION.read_text())["profiles"] if x["domain_family"]=="ENGINEERING_REPAIR")
    ref=f"profiles/{meta['profile_slug']}/SKILL.md"
    full=git_show(ROOT,c["baseline_revision"],ref)
    projection=section_projection(full,meta["include_sections"])
    full_src,model_src,revision=arm_sources(full,projection,meta["evolution_addendum"],"D_EVOLUTION_TARGET",ref)
    raw=json.loads((ROOT/"pexp_r3_producer_raw.json").read_text())
    a=next(x for x in raw["batches"] if x["profile_slug"]=="systemic_root_cause_repair_lf" and x["arm"]=="A_ORIGINAL" and x["batch_index"]==1)
    child=next(x for x in raw["cases"] if x["case_id"]=="PEXR-001")["arms"]["B_UPDATER_V01"]["case_execution_receipt"]
    return meta,full_src,model_src,revision,a["profile_execution_receipt"]["receipt_sha256"],child["parent_profile_execution_receipt_sha256"]

def make_contract(runid,meta,revision,prompt,model):
    return build_execution_contract(
        run_id=runid,profile_code=meta["profile_code"],profile_version=revision,
        objective="Determine whether frozen benchmark parent/child receipts establish verified causal continuity",
        authorized_scope=[f"campaign:{CAMPAIGN}",f"profile:{meta['profile_code']}","test_only_no_writes"],
        current_gate="PE10E_C4_PILOT_ONLY",
        allowed_actions=["MODEL_RUNTIME_EXECUTE","RAW_CAPTURE"],
        forbidden_actions=["PROFILE_AUTHORITY_WRITE","CAPABILITY_PROMOTION","RUNTIME_ACTIVATION","PRODUCTION_ACTIVATION"],
        required_checks=["PROFILE_SOURCE_BINDING","RUNTIME_ATTESTATION","RAW_CAPTURE"],
        required_evidence=["profile_execution","runtime_attestation","raw_output"],
        closure_conditions=["RAW_FROZEN","NO_WRITE","NO_PROMOTION"],
        input_governance_ref="pilot://PE-CAUSAL/frozen-scope",
        card_refs_and_hashes=[],
        adapter_ref="hetzner-local-llamacpp-http-v1",
        context_fingerprint=canonical_json_sha256({"campaign":CAMPAIGN,"run":runid,"prompt_sha":sha256_text(prompt),"model_sha":sha256_text(model[0]["content"])}),
        tool_permissions=["LOOPBACK_MODEL_RUNTIME"],executor_mode="REMOTE_API",
        card_resolution={"mode":"GENERIC_SAFE","critical_authority_missing":False,
            "unresolved_capabilities":[],"core_policy_ref":"pilot://PE-CAUSAL/frozen",
            "core_policy_sha256":sha256_text(CAMPAIGN+TASK),
            "fallback_reason":"Bounded test-only isolated frozen receipt comparison."})

def main():
    if OUTPUT.exists():raise SystemExit("PILOT_ALREADY_RAN")
    meta,full,model,revision,parent_sha,child_parent_sha=load_context()
    assert parent_sha!=child_parent_sha
    l=json.loads(LIVENESS.read_text())
    assert l["status"]=="SUBCAPABILITY_E2E_PASS_NOT_FULL_CAUSAL_ANALYSIS"
    cross=next(x for x in l["tests"] if x["case"]=="CROSS_EXECUTION_ACTUAL_CHILD")
    assert cross["state"]=="UNLINKED"
    settings=dataclasses.replace(Settings.from_env(),max_output_tokens=256,llama_timeout_seconds=180)
    client=LlamaHTTPClient(settings)
    raw_schema=json.dumps(SCHEMA,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
    schema=SchemaBinding(payload=SCHEMA,raw=raw_schema,sha256=hashlib.sha256(raw_schema).hexdigest(),source_refs=("pilot://causal-schema",),mode="BENCHMARK")
    structural={"schema":"lf-profile-runtime-queue-context/v1","source":"QUEUE_NATIVE_TEXT_PROFILE","screen_governance_applicable":False,"downstream_authorized":False,"benchmark_campaign":CAMPAIGN}
    common=("On frozen evidence, a producer execution receipt and a child execution receipt share case PEXR-001 but belong to different actual runs. "
            "A requested transition cites parent_sha="+parent_sha+" while the child crosslinks producer_sha="+child_parent_sha+". "
            "Determine whether the requested cross-run causal edge is established, and whether transition may proceed. "
            "Answer under the governed profile. Never infer causal validity from matching case identifiers alone.")
    runs=[]
    for arm in ("D1_STATIC","D3_WITH_VERIFIED_LINEAGE"):
        prompt=common
        if arm=="D3_WITH_VERIFIED_LINEAGE":
            prompt+="\nVerified read-only capability output from CAUSAL_EFFECT_LINEAGE: "+json.dumps({
                "state":cross["state"],"reasons":cross["reasons"],
                "receipt_sha256":cross["receipt_sha256"],"readback_source":"frozen_R3_verified_receipts"},sort_keys=True)
        prompt+="\nReturn a JSON object satisfying the response schema."
        runid=f"{CAMPAIGN}:{arm}"
        contract=make_contract(runid,meta,revision,prompt,model)
        adapter=PersistentLlamaServerAdapter(settings=settings,client=client,schema=schema,structural_context=structural,image_bytes=None,image_media_type=None,model_profile_sources=model,generation_schema=schema.payload,execution_budget={"max_prompt_tokens":7600,"max_output_tokens":256})
        verifier=PersistentLlamaServerVerifier(settings=settings,schema=schema,structural_context=structural,model_profile_sources=model,generation_schema=schema.payload)
        request=build_runtime_request(execution_id=runid,profile_code=meta["profile_code"],profile_slug=meta["profile_slug"],profile_sources=full,input_literal=prompt)
        request["executor_mode"]="REMOTE_API";request["execution_contract_sha256"]=contract["contract_sha256"];request["execution_contract"]=contract
        request["request_sha256"]=canonical_json_sha256({k:v for k,v in request.items() if k!="request_sha256"})
        proxy=(len(adapter._system_prompt(request))+len(prompt)+2)//3
        assert proxy<=settings.llama_context_tokens-settings.max_output_tokens-256,proxy
        start=time.perf_counter()
        result=execute_contract_bound_profile_runtime(
            execution_contract=contract,execution_id=runid,
            profile_code=meta["profile_code"],profile_slug=meta["profile_slug"],
            profile_sources=full,input_literal=prompt,adapter=adapter,
            attestation_verifier=verifier,allow_test_doubles=False)
        answer=result["raw_output"]
        answer=json.loads(answer) if isinstance(answer,str) else answer
        assert set(answer)==set(SCHEMA["properties"])
        assert answer["causal_state"] in SCHEMA["properties"]["causal_state"]["enum"]
        assert answer["decision"] in SCHEMA["properties"]["decision"]["enum"]
        assert result["runtime_attestation_verification"]["verified"] is True
        run={"arm":arm,"run_id":runid,"profile_revision":revision,
             "prompt_sha256":sha256_text(prompt),"contract_sha256":contract["contract_sha256"],
             "attestation":result["runtime_attestation_verification"],
             "execution_receipt_sha256":result["receipt"]["receipt_sha256"],
             "answer":answer,"wall_ms":round((time.perf_counter()-start)*1000,2),
             "usage":adapter.last_completion.get("usage",{})}
        runs.append(run)
        print(json.dumps({"event":"PILOT_ARM_FROZEN","arm":arm,
                          "answer":answer,"wall_ms":run["wall_ms"]},sort_keys=True),flush=True)
        # Preserve each completed arm, if next fails, without pretending full completion.
        (ROOT/"pe_causal_pilot_progress.ndjson").open("a").write(json.dumps(run,sort_keys=True)+"\n")
    out={"schema":"PE_CAUSAL_PILOT_PRODUCER_RAW_V1","campaign":CAMPAIGN,
         "raw_frozen":True,"evaluator_opened":False,"method_liveness_ref":"pe_causal_provider_liveness_raw_v1.json",
         "single_case":True,"candidate_arms":runs,"cutover_eligible":False}
    OUTPUT.write_text(json.dumps(out,sort_keys=True,indent=2)+"\n")
    print(json.dumps({"status":"RAW_FROZEN","arms":len(runs),"sha256":hashlib.sha256(OUTPUT.read_bytes()).hexdigest()},sort_keys=True))
if __name__=="__main__":main()
