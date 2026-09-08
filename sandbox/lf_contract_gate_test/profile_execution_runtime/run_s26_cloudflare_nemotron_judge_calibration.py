#!/usr/bin/env python3
"""Frozen S26 Nemotron remote semantic-judge challenger calibration.

Six fresh labels are committed before first calibration output. Challenger only:
canonical Qwen2.5-VL-7B authority, production, routing and promotion remain unchanged.
"""
from __future__ import annotations
import argparse, hashlib, json, os, time, urllib.error, urllib.request
from pathlib import Path
from typing import Any

MODEL="@cf/nvidia/nemotron-3-120b-a12b"
PRIMARY_MODEL="@cf/meta/llama-3.3-70b-instruct-fp8-fast"
MAX_TOKENS=256
TIMEOUT_SECONDS=120
SYSTEM_TEXT="""You are a narrow semantic compliance classifier, not a task solver.
Judge only whether EVIDENCE directly establishes compliance with RULE.
Do not infer missing implementation facts from plausibility or adjectives.
Return COMPLIES only when evidence directly establishes the rule.
Return CONTRADICTS only when evidence explicitly violates the rule.
Return UNCERTAIN when evidence does not establish either.
Return exactly one JSON object: {\"verdict\":\"COMPLIES|CONTRADICTS|UNCERTAIN\",\"reason_code\":\"SHORT_MACHINE_CODE\"}.
"""
SCHEMA={"type":"object","additionalProperties":False,"properties":{"verdict":{"type":"string","enum":["COMPLIES","CONTRADICTS","UNCERTAIN"]},"reason_code":{"type":"string","minLength":2,"maxLength":80}},"required":["verdict","reason_code"]}
CALIBRATION=(
 {"id":"NM_CAL_POS_KEEP_ERROR_TEXT","expected":"COMPLIES","rule":"The treatment must preserve the existing inline error text.","evidence":"Keep the current inline error text unchanged and adjust only the spacing around it."},
 {"id":"NM_CAL_POS_NO_NEW_PRIMARY_ACTION","expected":"COMPLIES","rule":"Do not add another primary action to the screen.","evidence":"Retain the single existing primary action and add no additional primary action."},
 {"id":"NM_CAL_NEG_REMOVE_BACK_NAV","expected":"CONTRADICTS","rule":"The existing back navigation must remain available.","evidence":"Remove the current back navigation from the header to simplify the layout."},
 {"id":"NM_CAL_NEG_INVENT_TIMEOUT","expected":"CONTRADICTS","rule":"Do not invent a timeout duration unless governed evidence supplies one.","evidence":"Show a 45-second timeout even though the governed evidence provides no timeout duration."},
 {"id":"NM_CAL_UNCERTAIN_FOCUS_ORDER","expected":"UNCERTAIN","rule":"The revised layout must preserve the existing keyboard focus order.","evidence":"Rearrange the visual grouping so related fields appear closer together."},
 {"id":"NM_CAL_UNCERTAIN_LABEL_VISIBILITY","expected":"UNCERTAIN","rule":"The existing field label must remain visible at all times.","evidence":"Use a compact treatment for the field while preserving its meaning."},
)

def sha(v:str)->str:return hashlib.sha256(v.encode("utf-8")).hexdigest()

def parse_value(value:Any):
    if isinstance(value,dict) and value:
        parsed=value; raw=json.dumps(value,ensure_ascii=False,sort_keys=True); shape="object:"+",".join(sorted(value)); fenced=False
    elif isinstance(value,str) and value.strip():
        raw=value.strip(); shape=f"string:{len(raw)}"; fenced=raw.startswith("```"); parsed=json.loads(raw)
    else: raise RuntimeError("FINAL_CONTENT_EMPTY")
    if not isinstance(parsed,dict) or set(parsed)!={"verdict","reason_code"}: raise RuntimeError("FINAL_JSON_SHAPE_INVALID:"+shape)
    verdict=parsed.get("verdict"); reason=parsed.get("reason_code")
    if verdict not in {"COMPLIES","CONTRADICTS","UNCERTAIN"}: raise RuntimeError("FINAL_VERDICT_INVALID")
    if not isinstance(reason,str) or not 2<=len(reason)<=80: raise RuntimeError("FINAL_REASON_CODE_INVALID")
    return parsed,raw,shape,fenced

def extract(envelope:dict[str,Any]):
    result=envelope.get("result") if envelope.get("success") is True and isinstance(envelope.get("result"),dict) else envelope
    if not isinstance(result,dict): raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    if "response" in result:
        parsed,raw,shape,fenced=parse_value(result.get("response"))
    else:
        choices=result.get("choices")
        if not isinstance(choices,list) or not choices or not isinstance(choices[0],dict): raise RuntimeError("CHAT_CHOICES_MISSING")
        message=choices[0].get("message")
        if not isinstance(message,dict): raise RuntimeError("CHAT_MESSAGE_MISSING")
        parsed,raw,inner,fenced=parse_value(message.get("content")); shape="chat_content:"+inner
    usage=result.get("usage") if isinstance(result.get("usage"),dict) else {}
    return parsed,raw,shape,fenced,usage

def call(account:str,token:str,case:dict[str,str]):
    payload={"messages":[{"role":"system","content":SYSTEM_TEXT},{"role":"user","content":json.dumps({"rule":case["rule"],"evidence":case["evidence"]},ensure_ascii=False,sort_keys=True)}],"response_format":{"type":"json_schema","json_schema":SCHEMA},"stream":False,"temperature":0,"top_p":1,"seed":42,"max_completion_tokens":MAX_TOKENS}
    req=urllib.request.Request(f"https://api.cloudflare.com/client/v4/accounts/{account}/ai/run/{MODEL}",data=json.dumps(payload,ensure_ascii=False).encode(),headers={"Authorization":f"Bearer {token}","Content-Type":"application/json","Accept":"application/json"},method="POST")
    started=time.monotonic()
    try:
        with urllib.request.urlopen(req,timeout=TIMEOUT_SECONDS) as r: envelope=json.loads(r.read().decode())
    except urllib.error.HTTPError as exc:
        detail=exc.read().decode("utf-8","replace")[-600:].replace("\n"," "); raise RuntimeError(f"CLOUDFLARE_HTTP_{exc.code}:{detail}") from exc
    parsed,raw,shape,fenced,usage=extract(envelope)
    return parsed,raw,shape,fenced,usage,round(time.monotonic()-started,3)

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument("--result-path",type=Path,required=True); args=p.parse_args()
    account=os.getenv("CLOUDFLARE_ACCOUNT_ID","").strip(); token=os.getenv("CLOUDFLARE_AI_CANARY_TOKEN","").strip()
    if not account or not token: raise SystemExit("S26_NEMOTRON_CALIBRATION_BLOCK_CLOUDFLARE_SECRET")
    matrix_sha=hashlib.sha256(json.dumps(CALIBRATION,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
    results=[]; neurons=0.0; prompt=completion=0
    for case in CALIBRATION:
        item={"case_id":case["id"],"expected":case["expected"],"rule_sha256":sha(case["rule"]),"evidence_sha256":sha(case["evidence"]),"transport_status":"NOT_EXECUTED"}
        try:
            parsed,raw,shape,fenced,usage,elapsed=call(account,token,case)
            item.update({"transport_status":"PASS","observed":parsed["verdict"],"reason_code":parsed["reason_code"],"matches_expected":parsed["verdict"]==case["expected"],"provider_response_shape":shape,"fenced_output":fenced,"raw_output_sha256":sha(raw),"elapsed_s":elapsed,"usage":{str(k):v for k,v in usage.items() if isinstance(v,(int,float,bool)) or v is None}})
            try: neurons+=float(usage.get("neurons") or 0); prompt+=int(usage.get("prompt_tokens") or 0); completion+=int(usage.get("completion_tokens") or 0)
            except (TypeError,ValueError): pass
        except Exception as exc:
            item.update({"transport_status":"FAIL","matches_expected":False,"error":f"{type(exc).__name__}:{str(exc)[:700]}"})
        results.append(item)
    matched=sum(1 for x in results if x.get("matches_expected") is True and x.get("fenced_output") is False); transport=sum(1 for x in results if x.get("transport_status")=="PASS"); passed=matched==6 and transport==6
    out={"schema":"S26_NEMOTRON_REMOTE_JUDGE_CALIBRATION_V1","strategy":"S26","status":"CALIBRATION_PASS_CHALLENGER_ONLY" if passed else "FAIL_CLOSED","provider":"cloudflare_workers_ai","primary_model":PRIMARY_MODEL,"judge_challenger_model":MODEL,"semantic_oracle_distinct":True,"provider_infrastructure_shared":True,"full_independent_authority_proven":False,"calibration_frozen_before_output":True,"preflight_case_reused":False,"prior_candidate_cases_reused":False,"calibration_sha256":matrix_sha,"case_count":6,"transport_passed":transport,"matched_expected":matched,"retries":0,"max_tokens":MAX_TOKENS,"neurons":round(neurons,6),"prompt_tokens":prompt,"completion_tokens":completion,"cases":results,"authority_changed":False,"canonical_judge_authority":"QWEN2_5_VL_7B_Q4_K_M_UNCHANGED","promotion_authorized":False,"production_mutation":False,"model_download_executed":False,"local_model_fallback_used":False,"paid_fallback_used":False}
    args.result_path.write_text(json.dumps(out,ensure_ascii=False,indent=2,sort_keys=True)+"\n"); print("S26_NEMOTRON_JUDGE_CALIBRATION="+json.dumps(out,ensure_ascii=False,sort_keys=True)); return 0 if passed else 2
if __name__=="__main__": raise SystemExit(main())
