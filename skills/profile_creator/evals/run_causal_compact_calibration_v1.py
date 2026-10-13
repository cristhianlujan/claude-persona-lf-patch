#!/usr/bin/env python3
"""Known-case semantic-transport calibration; never count toward blind uplift."""
from __future__ import annotations
import dataclasses,hashlib,json,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path[:0]=[str(ROOT/"services/profile_runtime_api"),str(ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"),str(ROOT/"skills/profile_creator/evals")]
from run_profile_expert_behavior_remote_v3 import git_show,section_projection,arm_sources
from profile_execution_contract import build_execution_contract,canonical_json_sha256
from contract_bound_profile_runtime import execute_contract_bound_profile_runtime
from profile_runtime_api.llama import LlamaHTTPClient,PersistentLlamaServerAdapter,PersistentLlamaServerVerifier
from profile_runtime_api.repository import SchemaBinding
from profile_runtime_api.settings import Settings
from profile_runtime_api.hashing import sha256_text
from profile_runtime_runner import build_runtime_request

NAME="PE-CAUSAL-TRANSPORT-20261009-CALIB"
RAW=ROOT/"pe_causal_compact_calibration_raw_v1.json"
CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_disruptive_tasks_v1.json"
CONSUMER=ROOT/"pe_causal_disruptive_consumption_v1.json"
CBASE=ROOT/"skills/profile_creator/evals/profile_expert_behavior_campaign_remote_v3.json"
PROJECTION=ROOT/"skills/profile_creator/evals/profile_expert_benchmark_source_projection_v1.json"
IDS=["PE-CAUS-05","PE-CAUS-06"]

def main():
 assert not RAW.exists()
 corpus=json.loads(CORPUS.read_text())
 tasks={x["case_id"]:x for x in corpus["cases"]}
 method={x["case_id"]:x["stages"][-1] for x in json.loads(CONSUMER.read_text())["cases"]}
 # Test only transport of *existing* verified method plan, no new oracle.
 cases=[]
 for cid in IDS:
  x=method[cid]
  case=tasks[cid]
  cases.append({
   "case_id":cid,"scenario":case["scenario"],
   "hypotheses":[{"id":h["id"],"description":h["description"]} for h in case["hypotheses"]],
   "verified_method_plan":{"decision":x["reconciled_action"],
       "falsified":x["falsified_hypotheses"],
       "causality_proven":False,
       "unverified_probes":x["unverified_probes"],
       "method_receipt_sha256":x["receipt"]},
   "evidence_details":[{"probe":o["probe_id"],"value":o["observed"],
       "verifiable":o["source_kind"]=="primary_readback"} for o in case["observations"]]
  })
 prompt=("This is an already-verified read-only method result. Your role is to explain that result, NOT to override or recompute it. "
   "The verified_method_plan is authoritative for THIS TEST only. "
   "For each case copy its exact decision, falsified IDs and causality_proven=false. "
   "Explain in a short factual reason naming relevant probe IDs. "
   "If unverified_probes is nonempty, never treat those observations as proven. "
   "Do not invent a cause. Return JSON only. Cases are independent.\n"
   +json.dumps({"cases":cases},ensure_ascii=False,separators=(",",":")))
 campaign=json.loads(CBASE.read_text())
 meta=next(x for x in json.loads(PROJECTION.read_text())["profiles"] if x["domain_family"]=="ENGINEERING_REPAIR")
 ref=f"profiles/{meta['profile_slug']}/SKILL.md"
 full=git_show(ROOT,campaign["baseline_revision"],ref)
 projected=section_projection(full,meta["include_sections"])
 fs,ms,revision=arm_sources(full,projected,meta["evolution_addendum"],"D_EVOLUTION_TARGET",ref)
 schema_body={"type":"object","properties":{"answers":{"type":"array","minItems":2,"maxItems":2,
    "items":{"type":"object","properties":{
      "case_id":{"type":"string","enum":IDS},
      "decision":{"type":"string","enum":["INVESTIGATE_H1","INVESTIGATE_H2","COLLECT_MORE_EVIDENCE"]},
      "falsified":{"type":"array","items":{"type":"string","enum":["H1","H2"]},"maxItems":2},
      "causality_proven":{"type":"boolean"},
      "reason":{"type":"string","maxLength":180}},
      "required":["case_id","decision","falsified","causality_proven","reason"],"additionalProperties":False}}},
      "required":["answers"],"additionalProperties":False}
 blob=json.dumps(schema_body,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
 binding=SchemaBinding(payload=schema_body,raw=blob,sha256=hashlib.sha256(blob).hexdigest(),source_refs=("pilot://causal-transport-schema",),mode="BENCHMARK")
 settings=dataclasses.replace(Settings.from_env(),max_output_tokens=300,llama_timeout_seconds=210)
 runid=NAME+":D_COMPACT"
 contract=build_execution_contract(
    run_id=runid,profile_code=meta["profile_code"],profile_version=revision,
    objective="Summarize independently verified hypothesis decisions without altering them",
    authorized_scope=["calibration:known_cases","no_authority_write"],
    current_gate="PE10E_C4_KNOWN_CASE_CALIBRATION",
    allowed_actions=["MODEL_RUNTIME_EXECUTE","RAW_CAPTURE"],
    forbidden_actions=["PROFILE_AUTHORITY_WRITE","CAPABILITY_PROMOTION","RUNTIME_ACTIVATION","PRODUCTION_ACTIVATION"],
    required_checks=["PROFILE_SOURCE_BINDING","RUNTIME_ATTESTATION","RAW_CAPTURE"],
    required_evidence=["profile_execution","runtime_attestation","raw_output"],
    closure_conditions=["RAW_FROZEN","NO_WRITE","NO_PROMOTION"],
    input_governance_ref="calibration://causal-transport/known-cases",
    card_refs_and_hashes=[],adapter_ref="hetzner-local-llamacpp-http-v1",
    context_fingerprint=canonical_json_sha256({"calibration":NAME,"prompt_sha256":sha256_text(prompt)}),
    tool_permissions=["LOOPBACK_MODEL_RUNTIME"],executor_mode="REMOTE_API",
    card_resolution={"mode":"GENERIC_SAFE","critical_authority_missing":False,"unresolved_capabilities":[],
        "core_policy_ref":"calibration://known-cases",
        "core_policy_sha256":sha256_text(NAME),
        "fallback_reason":"Known-case contract-bound transport calibration only."})
 structural={"schema":"lf-profile-runtime-queue-context/v1","source":"QUEUE_NATIVE_TEXT_PROFILE",
             "screen_governance_applicable":False,"downstream_authorized":False,"benchmark_campaign":NAME}
 adapter=PersistentLlamaServerAdapter(settings=settings,client=LlamaHTTPClient(settings),schema=binding,structural_context=structural,
    image_bytes=None,image_media_type=None,model_profile_sources=ms,
    generation_schema=binding.payload,execution_budget={"max_prompt_tokens":7200,"max_output_tokens":300})
 verifier=PersistentLlamaServerVerifier(settings=settings,schema=binding,structural_context=structural,
    model_profile_sources=ms,generation_schema=binding.payload)
 preview=build_runtime_request(execution_id=runid,profile_code=meta["profile_code"],profile_slug=meta["profile_slug"],
    profile_sources=fs,input_literal=prompt)
 preview["executor_mode"]="REMOTE_API";preview["execution_contract_sha256"]=contract["contract_sha256"];preview["execution_contract"]=contract
 preview["request_sha256"]=canonical_json_sha256({k:v for k,v in preview.items() if k!="request_sha256"})
 proxy=(len(adapter._system_prompt(preview))+len(prompt)+2)//3
 assert proxy<=min(7200,settings.llama_context_tokens-300-256),(proxy,settings.llama_context_tokens)
 start=time.perf_counter()
 result=execute_contract_bound_profile_runtime(
   execution_contract=contract,execution_id=runid,profile_code=meta["profile_code"],
   profile_slug=meta["profile_slug"],profile_sources=fs,input_literal=prompt,
   adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False)
 ans=json.loads(result["raw_output"]) if isinstance(result["raw_output"],str) else result["raw_output"]
 assert sorted(x["case_id"] for x in ans["answers"])==sorted(IDS)
 assert result["runtime_attestation_verification"]["verified"] is True
 output={"schema":"PE_CAUSAL_COMPACT_CALIBRATION_RAW_V1","run_id":runid,
   "known_cases":IDS,"profile_revision":revision,"raw_frozen":True,"not_holdout":True,
   "tool_plans_embedded":True,"answer":ans,
   "receipt_sha256":result["receipt"]["receipt_sha256"],
   "runtime_attestation":result["runtime_attestation_verification"],
   "wall_ms":round((time.perf_counter()-start)*1000,2),
   "usage":adapter.last_completion.get("usage",{}),
   "production_activation":False,"cutover_eligible":False}
 RAW.write_text(json.dumps(output,sort_keys=True,indent=2,ensure_ascii=False)+"\n")
 print(json.dumps({"status":"RAW_FROZEN","answers":ans["answers"],
   "wall_ms":output["wall_ms"],"sha256":hashlib.sha256(RAW.read_bytes()).hexdigest()},sort_keys=True),flush=True)
if __name__=="__main__":main()
