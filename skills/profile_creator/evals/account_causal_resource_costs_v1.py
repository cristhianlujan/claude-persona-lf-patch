#!/usr/bin/env python3
"""Matched-source resource accounting for exploratory D1/D2/D3 arms.

No assumed dollar price/token. Unmatched overhead and cache read/write
costs explicitly remain unknown.
"""
from pathlib import Path
import hashlib
import json

ROOT=Path(__file__).resolve().parents[3]
MODEL=ROOT/"skills/profile_creator/evals/results/pe_causal_remaining_holdout_model_raw_v1.json"
METHOD=ROOT/"skills/profile_creator/evals/results/pe_causal_unseen_method_raw_v1.json"
OUT=ROOT/"skills/profile_creator/evals/results/pe_causal_resource_accounting_v1.json"

def main():
    models=json.loads(MODEL.read_text())
    assert models["raw_frozen"]
    methods=json.loads(METHOD.read_text())
    accum={}
    for batch in models["batches"]:
        arm=batch["arm"]
        d=accum.setdefault(arm,{"batches":0,"cases":0,"model_prompt_tokens":0,
             "model_completion_tokens":0,"model_reported_cached_tokens":0,
             "model_wall_ms":0.0})
        d["batches"]+=1
        d["cases"]+=len(batch["case_ids"])
        d["model_prompt_tokens"]+=batch["usage"]["prompt_tokens"]
        d["model_completion_tokens"]+=batch["usage"]["completion_tokens"]
        d["model_reported_cached_tokens"]+=batch["usage"]["prompt_tokens_details"]["cached_tokens"]
        d["model_wall_ms"]+=batch["wall_ms"]
    for d in accum.values():
        d["model_total_tokens"]=d["model_prompt_tokens"]+d["model_completion_tokens"]
        d["model_wall_ms"]=round(d["model_wall_ms"],3)
    # These measured submethod milliseconds are NOT a measurement of
    # end-to-end selector, orchestration, evidence-acquisition or gate overhead.
    selected={"HCA-105","HCA-106","HCA-107","HCA-108"}
    samples=[receipt["receipt"]["observed_wall_ms"]
             for case in methods["cases"] if case["case_id"] in selected
             for receipt in case["stages"]]
    assert len(selected)==4 and len(samples)==5
    summary={"schema":"PE_CAUSAL_RESOURCE_ACCOUNTING_V1",
      "status":"OBSERVED_RESOURCE_COSTS_UNMATCHED_CONTEXT_LENGTH",
      "model_raw_sha256":hashlib.sha256(MODEL.read_bytes()).hexdigest(),
      "scope":"FOUR_SYNTHETIC_CASES",
      "arms":accum,
      "candidate_method_invocations":len(samples),
      "candidate_method_reported_wall_ms_sum":round(sum(samples),4),
      "excluded_costs":["selector_compute","precondition_readback","evidence_injection",
        "data_acquisition","typed_consumption","semantic_judging","model_cache_management"],
      "cost_qualifier":"Prompt tokens differ between arms; same model, unequal context.",
      "dollar_costs":"NOT_MEASURED","statistical_efficiency":"NOT_ESTABLISHED",
      "cutover_eligible":False}

    encoded=json.dumps(summary,sort_keys=True,indent=2)+"\n"
    if OUT.exists():
        assert OUT.read_text()==encoded, 'FROZEN_ARTIFACT_DRIFT'
    else:
        OUT.write_text(encoded)
    print(json.dumps({"D1":a,"D3":b,
       "completion_and_prompt_token_ratio_D3_to_D1":round(b["model_total_tokens"]/a["model_total_tokens"],4),
       "walltime_ratio_D3_to_D1":round(b["model_wall_ms"]/a["model_wall_ms"],4),
       "method_ms_excluding_other_orchestration":sum(samples)},sort_keys=True))

if __name__=="__main__":main()
