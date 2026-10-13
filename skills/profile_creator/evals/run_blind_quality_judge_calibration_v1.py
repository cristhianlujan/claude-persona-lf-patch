#!/usr/bin/env python3
"""Blind-labelled semantic judge calibration on frozen causal explanations.

This is a separate QUALITY_REVIEW execution with SAME Llama base model.
It is NOT a third-party independent evaluator or formal assurance.
"""
from __future__ import annotations
import dataclasses, hashlib, json, sys, time
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

NAME="PE-CAUSAL-QUALITY-REVIEW-20261009-CALIB"
RAW=ROOT/"pe_causal_blind_quality_judge_raw_v1.json"
PROJECTION=ROOT/"skills/profile_creator/evals/profile_expert_benchmark_source_projection_v1.json"
CBASE=ROOT/"skills/profile_creator/evals/profile_expert_behavior_campaign_remote_v3.json"
CASES=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
PRODUCER=ROOT/"pe_causal_remaining_holdout_model_raw_v1.json"
SCHEMA={"type":"object","properties":{"reviews":{
 "type":"array","minItems":4,"maxItems":4,
 "items":{"type":"object","properties":{
 "review_id":{"type":"string","enum":["S01","S02","S03","S04"]},
 "verdict":{"type":"string","enum":["SUPPORTED","CONTRADICTED","INSUFFICIENT_EVIDENCE","MIXED"]},
 "reason":{"type":"string","maxLength":250},
 "relevant_verified_probes":{"type":"array","items":{"type":"string"},"maxItems":4}
 },"required":["review_id","verdict","reason","relevant_verified_probes"],
 "additionalProperties":False}}},"required":["reviews"],"additionalProperties":False}

def digest(value):
 return hashlib.sha256(json.dumps(value,sort_keys=True,
             separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
def build_subjects():
 corpus={x["case_id"]:x for x in json.loads(CASES.read_text())["cases"]}
 raw=json.loads(PRODUCER.read_text())
 assert raw["raw_frozen"]
 reasons={}
 for batch in raw["batches"]:
  if batch["arm"]!="D3_TYPED_METHOD":continue
  for a in batch["answers"]:reasons[a["case_id"]]=a["reason"]
 assert len(reasons)==4
 def verified_obs(cid):
  obs=[]
  for x in corpus[cid]["observations"]:
   token={"case_id":cid,"probe_id":x["probe_id"],
        "observed":x["observed"],"source":"fixture-primary-readback"}
   valid=x["evidence_ref"]=="fixture-verified://"+digest(token)
   obs.append({"probe_id":x["probe_id"],"value":x["observed"],"verified":valid})
  return obs
 # Mix model-produced explanations and independent factual positive controls,
 # without disclosing which is which to the judge.
 cases=[
  {"review_id":"S01","case_id":"HCA-105","text":reasons["HCA-105"]},
  {"review_id":"S02","case_id":"HCA-106","text":"The trusted readback shows VALID_ROWS_PERSISTED=true and ACK_WRITTEN=false. This refutes both H1 and H2; it does not prove causality."},
  {"review_id":"S03","case_id":"HCA-106","text":reasons["HCA-106"]},
  {"review_id":"S04","case_id":"HCA-105","text":"The verified OWNER_EXISTS=true contradicts the hypothesis that the owner is absent; TOKEN_VALID is not independently verified, so the token-invalid diagnosis cannot be declared proven."},
 ]
 return [{**x,"verified_observations":verified_obs(x["case_id"])} for x in cases]

def main():
 assert not RAW.exists()
 meta=next(x for x in json.loads(PROJECTION.read_text())["profiles"] if x["domain_family"]=="QUALITY_REVIEW")
 c=json.loads(CBASE.read_text())
 source=f"profiles/{meta['profile_slug']}/SKILL.md"
 baseline=git_show(ROOT,c["baseline_revision"],source)
 projected=section_projection(baseline,meta["include_sections"])
 full,model,revision=arm_sources(baseline,projected,meta["evolution_addendum"],"D_EVOLUTION_TARGET",source)
 subjects=build_subjects()
 prompt=("You are a blind, independent fact checker for this limited test. "
 "Do NOT infer causal proof from hypothesis consistency. Assess the factual "
 "claims in each provided text solely against the separately verified observations. "
 "CONTRADICTED means at least one concrete factual statement opposes a verified observation. "
 "SUPPORTED requires all concrete claims be entailed by verified facts or explicitly "
 "stated as uncertain. INSUFFICIENT_EVIDENCE means unsupported factual assertions "
 "without direct contradiction. MIXED means both supported and unsupported factual claims. "
 "Do not trust source labels of the text being reviewed. Output JSON only.\n"
 +json.dumps({"subjects":subjects},sort_keys=True,separators=(",",":")))
 settings=dataclasses.replace(Settings.from_env(),max_output_tokens=500,llama_timeout_seconds=240)
 client=LlamaHTTPClient(settings)
 blob=json.dumps(SCHEMA,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
 schema=SchemaBinding(payload=SCHEMA,raw=blob,sha256=hashlib.sha256(blob).hexdigest(),
                      source_refs=("pilot://blind-qa-semantic-judge",),mode="BENCHMARK")
 context={"schema":"lf-profile-runtime-queue-context/v1","source":"QUEUE_NATIVE_TEXT_PROFILE",
   "screen_governance_applicable":False,"downstream_authorized":False,"benchmark_campaign":NAME}
 runid=NAME+":QUALITY_REVIEW"
 contract=build_execution_contract(
   run_id=runid,profile_code=meta["profile_code"],profile_version=revision,
   objective="Review frozen causal explanations against independent verified observations",
   authorized_scope=["calibration:known-cases","separate-quality-review","test_only_no_writes"],
   current_gate="PE10E_C4_RESTRICTED_SEMANTIC_JUDGE_CALIBRATION",
   allowed_actions=["MODEL_RUNTIME_EXECUTE","RAW_CAPTURE"],
   forbidden_actions=["PROFILE_AUTHORITY_WRITE","CAPABILITY_PROMOTION","RUNTIME_ACTIVATION","PRODUCTION_ACTIVATION"],
   required_checks=["PROFILE_SOURCE_BINDING","RUNTIME_ATTESTATION","RAW_CAPTURE"],
   required_evidence=["profile_execution","runtime_attestation","raw_output"],
   closure_conditions=["RAW_FROZEN","NO_WRITE","NO_PROMOTION"],
   input_governance_ref="pilot://qa-separated-review/known-cases",
   card_refs_and_hashes=[],adapter_ref="hetzner-local-llamacpp-http-v1",
   context_fingerprint=canonical_json_sha256({"campaign":NAME,"prompt_sha":sha256_text(prompt)}),
   tool_permissions=["LOOPBACK_MODEL_RUNTIME"],executor_mode="REMOTE_API",
   card_resolution={"mode":"GENERIC_SAFE","critical_authority_missing":False,
      "unresolved_capabilities":[],"core_policy_ref":"pilot://qa-fact-check",
      "core_policy_sha256":sha256_text(NAME),
      "fallback_reason":"Isolated bounded semantic QA calibration; same base model."})
 adapter=PersistentLlamaServerAdapter(settings=settings,client=client,schema=schema,
    structural_context=context,image_bytes=None,image_media_type=None,
    model_profile_sources=model,generation_schema=schema.payload,
    execution_budget={"max_prompt_tokens":7200,"max_output_tokens":500})
 verifier=PersistentLlamaServerVerifier(settings=settings,schema=schema,
    structural_context=context,model_profile_sources=model,generation_schema=schema.payload)
 request=build_runtime_request(execution_id=runid,profile_code=meta["profile_code"],
    profile_slug=meta["profile_slug"],profile_sources=full,input_literal=prompt)
 request["executor_mode"]="REMOTE_API"
 request["execution_contract_sha256"]=contract["contract_sha256"]
 request["execution_contract"]=contract
 request["request_sha256"]=canonical_json_sha256({k:v for k,v in request.items() if k!="request_sha256"})
 proxy=(len(adapter._system_prompt(request))+len(prompt)+2)//3
 assert proxy<=min(7200,settings.llama_context_tokens-settings.max_output_tokens-256),f"PRECHECK:{proxy}"
 start=time.perf_counter()
 response=execute_contract_bound_profile_runtime(
     execution_contract=contract,execution_id=runid,
     profile_code=meta["profile_code"],profile_slug=meta["profile_slug"],
     profile_sources=full,input_literal=prompt,adapter=adapter,
     attestation_verifier=verifier,allow_test_doubles=False)
 reviews=json.loads(response["raw_output"]) if isinstance(response["raw_output"],str) else response["raw_output"]
 assert sorted(r["review_id"] for r in reviews["reviews"])==["S01","S02","S03","S04"]
 assert response["runtime_attestation_verification"]["verified"]
 doc={"schema":"PE_BLIND_SEPARATE_QUALITY_REVIEW_CALIBRATION_V1",
   "raw_frozen":True,"not_external_independent_assurance":True,
   "same_underlying_model_as_producer":True,"review_profile":"QUALITY_REVIEW",
   "producer_raw_sha256":hashlib.sha256(PRODUCER.read_bytes()).hexdigest(),
   "reviewer_source_revision":revision,
   "attestation":response["runtime_attestation_verification"],
   "receipt_sha256":response["receipt"]["receipt_sha256"],
   "review_ids_without_arm_disclosure":[x["review_id"] for x in subjects],
   "reviews":reviews["reviews"],"usage":adapter.last_completion.get("usage",{}),
   "wall_ms":round((time.perf_counter()-start)*1000,2),
   "cutover_eligible":False}
 RAW.write_text(json.dumps(doc,ensure_ascii=False,sort_keys=True,indent=2)+"\n")
 print(json.dumps({"status":"FROZEN","review_count":len(doc["reviews"]),
   "verdicts":[[x["review_id"],x["verdict"]] for x in doc["reviews"]],
   "sha256":hashlib.sha256(RAW.read_bytes()).hexdigest()},sort_keys=True))

if __name__=="__main__":main()
