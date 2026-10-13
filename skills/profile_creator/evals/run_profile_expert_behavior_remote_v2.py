#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

HERE=Path(__file__).resolve()
ROOT=HERE.parents[3]
CONTRACT_DIR=ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"
if str(CONTRACT_DIR) not in sys.path:
    sys.path.insert(0,str(CONTRACT_DIR))

from profile_execution_contract import build_execution_contract, canonical_json_sha256
from contract_bound_profile_runtime import execute_contract_bound_profile_runtime

try:
    from profile_runtime_api.hashing import sha256_text
    from profile_runtime_api.llama import LlamaHTTPClient, PersistentLlamaServerAdapter, PersistentLlamaServerVerifier
    from profile_runtime_api.repository import SchemaBinding
    from profile_runtime_api.settings import Settings
    from profile_runtime_api.profile_runtime_runner import build_runtime_request  # type: ignore
except ImportError:
    # build_runtime_request lives in the governance harness, not the deployed package.
    from profile_runtime_runner import build_runtime_request
    from profile_runtime_api.hashing import sha256_text
    from profile_runtime_api.llama import LlamaHTTPClient, PersistentLlamaServerAdapter, PersistentLlamaServerVerifier
    from profile_runtime_api.repository import SchemaBinding
    from profile_runtime_api.settings import Settings

ARMS=("A_ORIGINAL","B_UPDATER_V01","C_EVOLUTION_CURRENT","D_EVOLUTION_TARGET")
CHOICES=("A","B","C","D")
CAMPAIGN_ID="PEXP-R2-20261008"
ADAPTER_ID="hetzner-local-llamacpp-http-v1"
PROVIDER="local_llama_cpp_hetzner_persistent"
ADDENDUM_HEADER="## Profile Evolution V2 Candidate Addendum"

def git_show(repo:Path,ref:str,path:str)->str:
    return subprocess.check_output(["git","-C",str(repo),"show",f"{ref}:{path}"],text=True)

def sha256_bytes(raw:bytes)->str:
    return hashlib.sha256(raw).hexdigest()

def section_projection(content:str,names:list[str])->str:
    lines=content.splitlines()
    title=lines[0] if lines else ""
    sections:dict[str,list[str]]={}
    current=None
    for line in lines:
        if line.startswith("## "):
            current=line[3:].strip()
            sections.setdefault(current,[line])
        elif current is not None:
            sections[current].append(line)
    missing=[n for n in names if n not in sections]
    if missing:
        raise RuntimeError("SOURCE_PROJECTION_SECTION_MISSING:"+",".join(missing))
    chunks=["\n".join(sections[n]).strip() for n in names]
    return ((title+"\n\n") if title else "")+"\n\n".join(chunks)+"\n"

def answer_schema(case_ids:list[str])->dict[str,Any]:
    return {
      "type":"object",
      "properties":{
        "answers":{
          "type":"array","minItems":len(case_ids),"maxItems":len(case_ids),
          "items":{
            "type":"object",
            "properties":{
              "case_id":{"type":"string","enum":case_ids},
              "choice":{"type":"string","enum":list(CHOICES)}
            },
            "required":["case_id","choice"],"additionalProperties":False
          }
        }
      },
      "required":["answers"],"additionalProperties":False
    }

def input_literal(cases:list[dict[str,Any]])->str:
    compact=[{"id":c["case_id"],"question":c["prompt"],"options":c["options"]} for c in cases]
    return (
      "Solve every case independently using the governed profile. "
      "For each case choose exactly one option letter. Do not infer across cases. "
      "Return only the JSON object required by the bound schema.\n"
      + json.dumps({"cases":compact},ensure_ascii=False,separators=(",",":"))
    )

def schema_binding(payload:dict[str,Any])->SchemaBinding:
    raw=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
    return SchemaBinding(payload=payload,raw=raw,sha256=sha256_bytes(raw),source_refs=("benchmark://PEXP-R2/answer-schema",),mode="BENCHMARK")

def canonical_child_receipt(batch_receipt:dict[str,Any],case_id:str,arm:str,choice:str,profile_revision:str)->dict[str,Any]:
    child={
      "schema":"PROFILE_EXPERT_CASE_EXECUTION_RECEIPT_V1",
      "campaign_id":CAMPAIGN_ID,
      "case_id":case_id,
      "arm":arm,
      "profile_revision":profile_revision,
      "producer_execution_id":batch_receipt["execution_id"],
      "parent_profile_execution_receipt_sha256":batch_receipt["receipt_sha256"],
      "choice":choice,
      "choice_sha256":sha256_text(choice),
      "downstream_authorized":False
    }
    child["receipt_sha256"]=canonical_json_sha256(child)
    return child

def validate_answers(raw_output:Any,case_ids:list[str])->dict[str,str]:
    if isinstance(raw_output,str):
        parsed=json.loads(raw_output)
    else:
        parsed=raw_output
    if not isinstance(parsed,dict) or not isinstance(parsed.get("answers"),list):
        raise RuntimeError("BATCH_ANSWERS_INVALID")
    rows=parsed["answers"]
    if len(rows)!=len(case_ids):
        raise RuntimeError("BATCH_ANSWER_COUNT_MISMATCH")
    out={}
    for row in rows:
        if not isinstance(row,dict) or row.get("case_id") not in case_ids or row.get("choice") not in CHOICES:
            raise RuntimeError("BATCH_ANSWER_ITEM_INVALID")
        if row["case_id"] in out:
            raise RuntimeError("BATCH_ANSWER_DUPLICATE")
        out[row["case_id"]]=row["choice"]
    if set(out)!=set(case_ids):
        raise RuntimeError("BATCH_ANSWER_CASE_SET_MISMATCH")
    return out

def make_contract(*,campaign_raw:bytes,run_id:str,profile_code:str,profile_version:str,objective:str,case_ids:list[str],context_fingerprint:str)->dict[str,Any]:
    campaign_sha=sha256_bytes(campaign_raw)
    return build_execution_contract(
      run_id=run_id,profile_code=profile_code,profile_version=profile_version,
      objective=objective,
      authorized_scope=[f"campaign:{CAMPAIGN_ID}",f"profile:{profile_code}",f"cases:{case_ids[0]}..{case_ids[-1]}"],
      current_gate="PE10E_C4",
      allowed_actions=["MODEL_RUNTIME_EXECUTE","RAW_CAPTURE"],
      forbidden_actions=["PROFILE_AUTHORITY_WRITE","CAPABILITY_PROMOTION","RUNTIME_ACTIVATION","PRODUCTION_ACTIVATION","CROSS_CASE_INFERENCE"],
      required_checks=["PROFILE_SOURCE_BINDING","RUNTIME_ATTESTATION","RAW_CAPTURE"],
      required_evidence=["profile_execution","runtime_attestation","raw_output"],
      closure_conditions=["RAW_FROZEN","NO_WRITE","NO_PROMOTION"],
      input_governance_ref=f"github://campaign/{CAMPAIGN_ID}/frozen-task-corpus",
      card_refs_and_hashes=[],
      adapter_ref=ADAPTER_ID,
      context_fingerprint=context_fingerprint,
      tool_permissions=["LOOPBACK_MODEL_RUNTIME"],
      executor_mode="REMOTE_API",
      card_resolution={
        "mode":"GENERIC_SAFE","critical_authority_missing":False,"unresolved_capabilities":[],
        "core_policy_ref":"skills/profile_creator/evals/profile_expert_behavior_campaign_remote_v2.json",
        "core_policy_sha256":campaign_sha,
        "fallback_reason":"Frozen benchmark corpus is fully bound; no JIT card is required."
      }
    )

def arm_sources(full:str,projection:str,addendum:str,arm:str,ref:str)->tuple[list[dict[str,str]],list[dict[str,str]],str]:
    if arm=="D_EVOLUTION_TARGET":
        full_candidate=full.rstrip()+"\n\n"+ADDENDUM_HEADER+"\n"+addendum.strip()+"\n"
        model_candidate=projection.rstrip()+"\n\n"+ADDENDUM_HEADER+"\n"+addendum.strip()+"\n"
        revision="candidate:"+sha256_text(full_candidate)
        return [{"ref":ref,"content":full_candidate}],[{"ref":ref,"content":model_candidate}],revision
    revision="baseline:"+sha256_text(full)
    return [{"ref":ref,"content":full}],[{"ref":ref,"content":projection}],revision

def run(args:argparse.Namespace)->int:
    campaign_path=Path(args.campaign); tasks_path=Path(args.tasks); projection_path=Path(args.projection)
    if any("oracle" in p.name.lower() or "holdout" in p.name.lower() for p in (campaign_path,tasks_path,projection_path)):
        raise RuntimeError("PRODUCER_FORBIDDEN_FILE")
    campaign_raw=campaign_path.read_bytes()
    campaign=json.loads(campaign_raw)
    tasks=json.loads(tasks_path.read_text())
    projection=json.loads(projection_path.read_text())
    if campaign.get("campaign_id")!=CAMPAIGN_ID or campaign.get("raw_generation_started") is not False:
        raise RuntimeError("CAMPAIGN_NOT_FROZEN_PRE_RAW")
    if campaign.get("route",{}).get("adapter_id")!=ADAPTER_ID:
        raise RuntimeError("ADAPTER_MISMATCH")
    if len(tasks.get("cases",[]))!=campaign["planned_case_count"]:
        raise RuntimeError("CASE_COUNT_MISMATCH")

    repo=Path(args.repo_root).resolve()
    settings=dataclasses.replace(Settings.from_env(),max_output_tokens=256,llama_timeout_seconds=240)
    client=LlamaHTTPClient(settings)
    structural={"schema":"lf-profile-runtime-queue-context/v1","source":"QUEUE_NATIVE_TEXT_PROFILE","screen_governance_applicable":False,"downstream_authorized":False,"benchmark_campaign":CAMPAIGN_ID}
    max_batch=int(campaign["batching"]["max_cases_per_model_call"])
    by_slug:dict[str,list[dict[str,Any]]]={}
    for c in tasks["cases"]:
        by_slug.setdefault(c["profile_slug"],[]).append(c)
    pmeta={p["profile_slug"]:p for p in projection["profiles"]}

    preflight=[]
    batches=[]
    cases_out={c["case_id"]:{
      "case_id":c["case_id"],"domain_family":c["domain_family"],"difficulty":c["difficulty"],
      "critical":c["critical"],"preservation_case":c["preservation_case"],
      "adaptation_case":c["adaptation_case"],"transfer_case":c["transfer_case"],"arms":{}
    } for c in tasks["cases"]}

    for slug in sorted(by_slug):
        meta=pmeta[slug]
        ref=f"profiles/{slug}/SKILL.md"
        full=git_show(repo,campaign["baseline_revision"],ref)
        projection_text=section_projection(full,meta["include_sections"])
        if len(projection_text)>projection["max_projected_chars"]:
            raise RuntimeError("SOURCE_PROJECTION_BUDGET_EXCEEDED:"+slug)
        profile_cases=sorted(by_slug[slug],key=lambda x:x["case_id"])
        partitions=[profile_cases[i:i+max_batch] for i in range(0,len(profile_cases),max_batch)]
        if [len(x) for x in partitions] != campaign["batching"]["batches_per_profile"]:
            raise RuntimeError("BATCH_PARTITION_MISMATCH:"+slug)
        for batch_index,batch_cases in enumerate(partitions,1):
            ids=[c["case_id"] for c in batch_cases]
            literal=input_literal(batch_cases)
            schema=schema_binding(answer_schema(ids))
            for arm in ARMS:
                full_sources,model_sources,profile_revision=arm_sources(full,projection_text,meta["evolution_addendum"],arm,ref)
                run_id=f"{CAMPAIGN_ID}:{slug}:B{batch_index}:{arm}"
                context_fingerprint=canonical_json_sha256({"campaign":CAMPAIGN_ID,"slug":slug,"batch":ids,"arm":arm,"model_source_sha":sha256_text(model_sources[0]["content"])})
                contract=make_contract(campaign_raw=campaign_raw,run_id=run_id,profile_code=meta["profile_code"],profile_version=profile_revision,objective="Choose the best governed expert action for each frozen benchmark case.",case_ids=ids,context_fingerprint=context_fingerprint)
                execution_budget={"max_prompt_tokens":7600,"max_output_tokens":256}
                adapter=PersistentLlamaServerAdapter(settings=settings,client=client,schema=schema,structural_context=structural,image_bytes=None,image_media_type=None,model_profile_sources=model_sources,generation_schema=schema.payload,execution_budget=execution_budget)
                verifier=PersistentLlamaServerVerifier(settings=settings,schema=schema,structural_context=structural,model_profile_sources=model_sources,generation_schema=schema.payload)

                preview=build_runtime_request(execution_id=run_id,profile_code=meta["profile_code"],profile_slug=slug,profile_sources=full_sources,input_literal=literal)
                preview["executor_mode"]="REMOTE_API";preview["execution_contract_sha256"]=contract["contract_sha256"];preview["execution_contract"]=contract
                preview["request_sha256"]=canonical_json_sha256({k:v for k,v in preview.items() if k!="request_sha256"})
                system_prompt=adapter._system_prompt(preview)
                prompt_proxy=(len(system_prompt)+len(literal)+2)//3
                available=settings.llama_context_tokens-settings.max_output_tokens-256
                pf={"run_id":run_id,"slug":slug,"batch":ids,"arm":arm,"prompt_proxy_tokens":prompt_proxy,"available_prompt_tokens":available,"full_source_sha256":sha256_text(full_sources[0]["content"]),"model_source_sha256":sha256_text(model_sources[0]["content"])}
                preflight.append(pf)
                if prompt_proxy>min(7600,available):
                    raise RuntimeError(f"PROMPT_PREFLIGHT_EXCEEDED:{run_id}:{prompt_proxy}>{min(7600,available)}")
                if args.preflight_only:
                    continue

                t=time.perf_counter()
                result=execute_contract_bound_profile_runtime(
                  execution_contract=contract,execution_id=run_id,profile_code=meta["profile_code"],profile_slug=slug,
                  profile_sources=full_sources,input_literal=literal,adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False
                )
                wall_ms=round((time.perf_counter()-t)*1000,3)
                answers=validate_answers(result["raw_output"],ids)
                receipt=result["receipt"]
                batch_rec={
                  "run_id":run_id,"profile_slug":slug,"arm":arm,"batch_index":batch_index,"case_ids":ids,
                  "profile_revision":profile_revision,"profile_full_source_sha256":sha256_text(full_sources[0]["content"]),
                  "profile_model_source_sha256":sha256_text(model_sources[0]["content"]),
                  "execution_contract_sha256":contract["contract_sha256"],
                  "profile_execution_receipt":receipt,
                  "runtime_attestation_verification":result["runtime_attestation_verification"],
                  "raw_output_sha256":sha256_text(result["raw_output"] if isinstance(result["raw_output"],str) else json.dumps(result["raw_output"],sort_keys=True)),
                  "wall_ms":wall_ms,"usage":adapter.last_completion.get("usage",{}),"timings":adapter.last_completion.get("timings",{}),
                  "finish_reason":adapter.last_completion.get("finish_reason")
                }
                batches.append(batch_rec)
                for cid in ids:
                    child=canonical_child_receipt(receipt,cid,arm,answers[cid],profile_revision)
                    cases_out[cid]["arms"][arm]={
                      "choice":answers[cid],"profile_revision":profile_revision,
                      "producer_execution_id":run_id,
                      "execution_receipt_ref":f"producer_raw://{CAMPAIGN_ID}/{cid}/{arm}",
                      "execution_receipt_sha256":child["receipt_sha256"],
                      "case_execution_receipt":child,
                      "parent_execution_receipt_sha256":receipt["receipt_sha256"],
                      "profile_full_source_sha256":sha256_text(full_sources[0]["content"]),
                      "profile_model_source_sha256":sha256_text(model_sources[0]["content"])
                    }

    if args.preflight_only:
        print(json.dumps({"status":"PASS","campaign_id":CAMPAIGN_ID,"preflight_count":len(preflight),"max_prompt_proxy_tokens":max(x["prompt_proxy_tokens"] for x in preflight),"min_headroom_tokens":min(x["available_prompt_tokens"]-x["prompt_proxy_tokens"] for x in preflight)},sort_keys=True))
        return 0

    for c in cases_out.values():
        if set(c["arms"])!=set(ARMS):
            raise RuntimeError("CASE_ARMS_INCOMPLETE:"+c["case_id"])
    total_wall=sum(float(b["wall_ms"]) for b in batches)
    prompt_tokens=sum(int((b.get("usage") or {}).get("prompt_tokens",0) or 0) for b in batches)
    completion_tokens=sum(int((b.get("usage") or {}).get("completion_tokens",0) or 0) for b in batches)
    output={
      "schema":"PROFILE_EXPERT_BEHAVIOR_PRODUCER_RAW_V2",
      "campaign_id":CAMPAIGN_ID,"benchmark_scope":"EXPERT_TASK_PERFORMANCE_E2E",
      "producer_route":"REMOTE_API","adapter_id":ADAPTER_ID,"provider":PROVIDER,
      "raw_frozen":True,"oracle_opened":False,"holdout_opened":False,"scoring_opened":False,
      "thresholds_frozen_before_raw":True,
      "case_count":len(cases_out),"batch_execution_count":len(batches),
      "preflight":{"max_prompt_proxy_tokens":max(x["prompt_proxy_tokens"] for x in preflight),"min_headroom_tokens":min(x["available_prompt_tokens"]-x["prompt_proxy_tokens"] for x in preflight)},
      "resource_metrics":{"cost_budget_pass":True,"incremental_monetary_cost":0,"latency_observed":True,"total_wall_ms":round(total_wall,3),"token_status":"OBSERVED","prompt_tokens":prompt_tokens,"completion_tokens":completion_tokens,"token_estimated":False},
      "batches":batches,"cases":[cases_out[k] for k in sorted(cases_out)]
    }
    raw=json.dumps(output,ensure_ascii=False,indent=2,sort_keys=True)+"\n"
    Path(args.output).write_text(raw)
    print(json.dumps({"status":"PASS","campaign_id":CAMPAIGN_ID,"case_count":len(cases_out),"batch_execution_count":len(batches),"producer_raw_sha256":sha256_text(raw),"total_wall_ms":round(total_wall,3),"prompt_tokens":prompt_tokens,"completion_tokens":completion_tokens},sort_keys=True))
    return 0

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--campaign",required=True);ap.add_argument("--tasks",required=True);ap.add_argument("--projection",required=True)
    ap.add_argument("--repo-root",required=True);ap.add_argument("--output",required=True)
    ap.add_argument("--preflight-only",action="store_true")
    return run(ap.parse_args())
if __name__=="__main__": raise SystemExit(main())
