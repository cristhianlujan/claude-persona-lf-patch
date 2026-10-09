#!/usr/bin/env python3
"""Frozen paired D1 vs D3 disruptive hypothesis model experiment.

No evaluator/oracle imported. Both arms receive same model profile and raw
evidence; only D3 receives bounded test-only verified method outputs.
"""
from __future__ import annotations
import dataclasses, hashlib, json, sys,time
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

CAMPAIGN="PE-CAUSAL-D2-REAL-SELECTOR-V3-20261009"
CORPUS=ROOT/"skills/profile_creator/evals/profile_causal_unseen_holdout_remaining_v1.json"
CORPUS_SHA="4f3009b78989ee43e44c895f78d747df50f20daf4a31a604193f742bfe66cd8b"
METHOD=ROOT/"pe_causal_unseen_remaining_cards_v1.json"
METHOD_SHA="883119d7c7caaa7f94523032f32a43acdca664c0f44696a44a53607466adcde8"
OUTPUT=ROOT/"pe_causal_d2_real_v3_model_raw_v1.json"
PROGRESS=ROOT/"pe_causal_d2_real_v3_progress.ndjson"
SELECTOR_RAW=ROOT/"pe_causal_v3_selector_real_receipts_v1.json"
SELECTOR_SHA="02dbec96739e5a02b21ab5f1775ef113143ec0a4ee045f0d6710b7e6ab20089e"
ARMS=["D2_SELECTOR_ONLY"]
BATCH_SIZE=2
BASE=ROOT/"skills/profile_creator/evals/profile_expert_behavior_campaign_remote_v3.json"
PROJECTION=ROOT/"skills/profile_creator/evals/profile_expert_benchmark_source_projection_v1.json"

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def json_schema(ids):
 return {"type":"object","properties":{
    "answers":{"type":"array","minItems":len(ids),"maxItems":len(ids),
      "items":{"type":"object","properties":{
        "case_id":{"type":"string","enum":ids},
        "decision":{"type":"string","enum":["INVESTIGATE_H1","INVESTIGATE_H2","INVESTIGATE_H3","COLLECT_MORE_EVIDENCE"]},
        "falsified":{"type":"array","items":{"type":"string","enum":["H1","H2"]},"maxItems":3},
        "causality_proven":{"type":"boolean"},
        "reason":{"type":"string","maxLength":180},
        "claim_ids":{"type":"array","items":{"type":"string"},"maxItems":9}},
        "required":["case_id","decision","falsified","causality_proven","reason","claim_ids"],
        "additionalProperties":False}}},
    "required":["answers"],"additionalProperties":False}
def contract(run_id,profile_code,revision,campaign_sha,model_sha):
 return build_execution_contract(
    run_id=run_id,profile_code=profile_code,profile_version=revision,
    objective="Evaluate competing causal hypotheses from explicitly supplied verified/unverified observations",
    authorized_scope=[f"campaign:{CAMPAIGN}","non_authority_paired_evaluation"],
    current_gate="PE10E_C4_DISRUPTIVE_PILOT",
    allowed_actions=["MODEL_RUNTIME_EXECUTE","RAW_CAPTURE"],
    forbidden_actions=["PROFILE_AUTHORITY_WRITE","CAPABILITY_PROMOTION","RUNTIME_ACTIVATION","PRODUCTION_ACTIVATION"],
    required_checks=["PROFILE_SOURCE_BINDING","RUNTIME_ATTESTATION","RAW_CAPTURE"],
    required_evidence=["profile_execution","runtime_attestation","raw_output"],
    closure_conditions=["RAW_FROZEN","NO_WRITE","NO_PROMOTION"],
    input_governance_ref="pilot://PE-CAUSAL-DISRUPTIVE/corpus-frozen",
    card_refs_and_hashes=[],adapter_ref="hetzner-local-llamacpp-http-v1",
    context_fingerprint=canonical_json_sha256({"campaign":CAMPAIGN,"run":run_id,
        "campaign_sha":campaign_sha,"profile_model_sha":model_sha}),
    tool_permissions=["LOOPBACK_MODEL_RUNTIME"],executor_mode="REMOTE_API",
    card_resolution={"mode":"GENERIC_SAFE","critical_authority_missing":False,
        "unresolved_capabilities":[],"core_policy_ref":"pilot://PE-CAUSAL-DISRUPTIVE/frozen-corpus",
        "core_policy_sha256":campaign_sha,
        "fallback_reason":"Frozen reversible execution only, no profile authority change."})

def prompt_for(cases,arm,method_by_id):
 rows=[]
 for case in cases:
  row={"case_id":case["case_id"],"scenario":case["scenario"],
       "hypotheses":case["hypotheses"],"observations":case["observations"]}
  if arm=="D3_TYPED_METHOD":
   card=method_by_id[case["case_id"]]
   row["verified_method_card"]={
     "method_decision":card["method_decision"],
     "falsified_hypotheses":card["falsified_hypotheses"],
     "method_receipt_sha256":card["method_receipt_sha256"],
     "supported_claims":[{"claim_id":c["claim_id"],"text":c["text"],
       "evidence_refs":c["evidence_refs"]} for c in card["supported_claims"]]}
  if arm=="D2_SELECTOR_ONLY":
   receipt=method_by_id[case["case_id"]]
   sel=receipt["selection"]
   row["selector_receipt"]={"selector_version":"V3_ACTUALLY_EXECUTED",
      "receipt_sha256":receipt["selection_sha256"],
      "method_id":receipt["method_id"],
      "precondition_state":sel["selected_methods"][0]["precondition_receipt"]["status"],
      "cost_points":sel["estimated_or_observed_cost"]["method_cost_points"],
      "execution_authorized":sel["execution_authorized"],
      "method_execution":"NOT_EXECUTED",
      "selection_is_not_causal_evidence":True}
  rows.append(row)
 return ("Evaluate competing causal hypotheses and do not claim final causality. "
   "If a verified_method_card is supplied, copy method_decision and "
   "falsified_hypotheses verbatim, and select all decisive claim IDs "
   "(REFUTE: and MISSING:) plus helpful OBS: IDs. Do not invent citations. "
   "Without a card reason independently from provided observations and return claim_ids=[]. "
   "Selector metadata is advisory only and has NO executed method evidence; "
   "never invent tool results or treat selection as falsification proof. "
   "When competing hypotheses survive or crucial observations are unverified, "
   "choose COLLECT_MORE_EVIDENCE. Return one JSON object, cases independent.\n"
   +json.dumps({"cases":rows},ensure_ascii=False,separators=(",",":")))

def main():
 assert not OUTPUT.exists() and not PROGRESS.exists()
 assert sha(CORPUS)==CORPUS_SHA and sha(SELECTOR_RAW)==SELECTOR_SHA
 corpus=json.loads(CORPUS.read_text())
 m=json.loads(SELECTOR_RAW.read_text());assert m["status"] == "FROZEN_NON_AUTHORITY_SELECTION" and m["cutover_eligible"] is False and len(m["receipts"]) == len(corpus["cases"])
 by_id={c["case_id"]:c for c in m["receipts"]}
 for case in corpus["cases"]:
  receipt=by_id[case["case_id"]]
  assert receipt["source_evidence_refs"]==[o["evidence_ref"] for o in case["observations"]]
  assert canonical_json_sha256(receipt["selection"])==receipt["selection_sha256"]
  assert receipt["method_execution"]=="NOT_EXECUTED"
  assert not receipt["selection"]["execution_authorized"]

 c=json.loads(BASE.read_text())
 projection=json.loads(PROJECTION.read_text())
 meta=next(x for x in projection["profiles"] if x["domain_family"]=="ENGINEERING_REPAIR")
 ref=f"profiles/{meta['profile_slug']}/SKILL.md"
 base=git_show(ROOT,c["baseline_revision"],ref)
 proj=section_projection(base,meta["include_sections"])
 full,model,revision=arm_sources(base,proj,meta["evolution_addendum"],"D_EVOLUTION_TARGET",ref)
 settings=dataclasses.replace(Settings.from_env(),max_output_tokens=750,llama_timeout_seconds=240)
 client=LlamaHTTPClient(settings)
 structural={"schema":"lf-profile-runtime-queue-context/v1",
     "source":"QUEUE_NATIVE_TEXT_PROFILE","screen_governance_applicable":False,
     "downstream_authorized":False,"benchmark_campaign":CAMPAIGN}
 all_batches=[];cases=corpus["cases"]
 partitions=[cases[i:i+BATCH_SIZE] for i in range(0,len(cases),BATCH_SIZE)]
 # Preflight every batch/arm before the FIRST model execution. No partial
 # modeled output may be produced when any arm exceeds token headroom.
 for trial_batch,batch in enumerate(partitions,1):
  ids=[x["case_id"] for x in batch]
  for trial_arm in ARMS:
   prompt=prompt_for(batch,trial_arm,by_id)
   schema_payload=json_schema(ids)
   blob=json.dumps(schema_payload,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
   schema=SchemaBinding(payload=schema_payload,raw=blob,sha256=hashlib.sha256(blob).hexdigest(),source_refs=("pilot://causal-recovered-schema",),mode="BENCHMARK")
   runid=f"{CAMPAIGN}:B{trial_batch}:{trial_arm}"
   chk=contract(runid,meta["profile_code"],revision,CORPUS_SHA,sha256_text(model[0]["content"]))
   adapter=PersistentLlamaServerAdapter(settings=settings,client=client,schema=schema,structural_context=structural,image_bytes=None,image_media_type=None,model_profile_sources=model,generation_schema=schema.payload,execution_budget={"max_prompt_tokens":7300,"max_output_tokens":750})
   request=build_runtime_request(execution_id=runid,profile_code=meta["profile_code"],profile_slug=meta["profile_slug"],profile_sources=full,input_literal=prompt)
   request["executor_mode"]="REMOTE_API";request["execution_contract_sha256"]=chk["contract_sha256"];request["execution_contract"]=chk
   request["request_sha256"]=canonical_json_sha256({k:v for k,v in request.items() if k!="request_sha256"})
   proxy=(len(adapter._system_prompt(request))+len(prompt)+2)//3
   available=settings.llama_context_tokens-750-256
   assert proxy<=min(7300,available),f"UPFRONT_CONTEXT_PREFLIGHT:{runid}:{proxy}/{available}"
   print(json.dumps({"event":"UPFRONT_PREFLIGHT_PASS","run_id":runid,"proxy":proxy,"available":available}),flush=True)
 for batchnum,batch in enumerate(partitions,1):
  ids=[x["case_id"] for x in batch]
  for arm in ARMS:
   prompt=prompt_for(batch,arm,by_id)
   schema_payload=json_schema(ids)
   blob=json.dumps(schema_payload,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
   schema=SchemaBinding(payload=schema_payload,raw=blob,sha256=hashlib.sha256(blob).hexdigest(),source_refs=("pilot://causal-disruptive-schema",),mode="BENCHMARK")
   rid=f"{CAMPAIGN}:B{batchnum}:{arm}"
   current=contract(rid,meta["profile_code"],revision,CORPUS_SHA,sha256_text(model[0]["content"]))
   adapter=PersistentLlamaServerAdapter(settings=settings,client=client,schema=schema,structural_context=structural,image_bytes=None,image_media_type=None,model_profile_sources=model,generation_schema=schema.payload,execution_budget={"max_prompt_tokens":7300,"max_output_tokens":750})
   verifier=PersistentLlamaServerVerifier(settings=settings,schema=schema,structural_context=structural,model_profile_sources=model,generation_schema=schema.payload)
   request=build_runtime_request(execution_id=rid,profile_code=meta["profile_code"],profile_slug=meta["profile_slug"],profile_sources=full,input_literal=prompt)
   request["executor_mode"]="REMOTE_API";request["execution_contract_sha256"]=current["contract_sha256"];request["execution_contract"]=current
   request["request_sha256"]=canonical_json_sha256({k:v for k,v in request.items() if k!="request_sha256"})
   proxy=(len(adapter._system_prompt(request))+len(prompt)+2)//3
   available=settings.llama_context_tokens-750-256
   assert proxy<=min(7300,available),f"CONTEXT_PREFLIGHT:{rid}:{proxy}/{available}"
   start=time.perf_counter()
   ret=execute_contract_bound_profile_runtime(
     execution_contract=current,execution_id=rid,profile_code=meta["profile_code"],
     profile_slug=meta["profile_slug"],profile_sources=full,input_literal=prompt,
     adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False)
   assert ret["runtime_attestation_verification"]["verified"] is True
   parsed=json.loads(ret["raw_output"]) if isinstance(ret["raw_output"],str) else ret["raw_output"]
   assert isinstance(parsed,dict) and len(parsed["answers"])==len(ids)
   assert sorted(a["case_id"] for a in parsed["answers"])==sorted(ids)
   assert all(a["decision"] in ("INVESTIGATE_H1","INVESTIGATE_H2","INVESTIGATE_H3","COLLECT_MORE_EVIDENCE") for a in parsed["answers"])
   one={"run_id":rid,"arm":arm,"batch_index":batchnum,"case_ids":ids,
        "prompt_sha256":sha256_text(prompt),"source_revision":revision,
        "source_model_sha256":sha256_text(model[0]["content"]),
        "contract_sha256":current["contract_sha256"],
        "receipt_sha256":ret["receipt"]["receipt_sha256"],
        "runtime_attestation":ret["runtime_attestation_verification"],
        "answers":parsed["answers"],
        "wall_ms":round((time.perf_counter()-start)*1000,2),
        "usage":adapter.last_completion.get("usage",{})}
   all_batches.append(one)
   with PROGRESS.open("a") as f:f.write(json.dumps(one,ensure_ascii=False,sort_keys=True)+"\n")
   print(json.dumps({"event":"ARM_FROZEN","arm":arm,"batch":batchnum,
       "case_ids":ids,"wall_ms":one["wall_ms"],
       "answers":parsed["answers"]},sort_keys=True),flush=True)
 output={"schema":"PE_CAUSAL_D2_REAL_SELECTOR_MODEL_RAW_V1",
  "campaign":CAMPAIGN,"corpus_sha256":CORPUS_SHA,"selector_sha256":SELECTOR_SHA,
  "raw_frozen":True,"oracle_opened":False,"score_opened":False,
  "retrospective_diagnostic_not_blind_holdout":True,
  "selector_real_v3_called_separately":True,
  "method_invocations":0,
  "selection_sha256_by_case":{k:v["selection_sha256"] for k,v in by_id.items()},
  "arms":ARMS,"batches":all_batches,"cutover_eligible":False}
 OUTPUT.write_text(json.dumps(output,ensure_ascii=False,indent=2,sort_keys=True)+"\n")
 print(json.dumps({"status":"FROZEN","model_batches":len(all_batches),
    "cases":len(cases),"output_sha256":sha(OUTPUT)},sort_keys=True),flush=True)
if __name__=="__main__":main()
