#!/usr/bin/env python3
"""Validate lossless routing of locked v0.2 visual observations into Story Pack cross-cutting sections.

The bridge does not invent product requirements. It proves that observable visual
facts are preserved by source_ref, token candidates are not promoted without a
registry, and responsive/accessibility facts that are not observable remain
pending unless external product evidence is explicitly supplied.
"""
from __future__ import annotations
import argparse, copy, json, sys
from pathlib import Path
from typing import Any
from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object, sha256_file

JUDGE = "VISUAL_EVIDENCE_BRIDGE"
VERSION = "v0.1"
TOKEN_TYPES = {"CONTROL","ICON","COLOR_APPEARANCE","TYPOGRAPHY_APPEARANCE","SPACING_APPEARANCE","SIZE_RADIUS_APPEARANCE","VISUAL_STATE","PROGRESS"}
MESSAGE_TYPES = {"COPY","PLACEHOLDER","LINK","CONSENT","SECURITY_TRUST"}
RESP_TYPES = {"RESPONSIVE","ACCESSIBILITY"}


def refs_from(items: Any) -> set[str]:
    out=set()
    if isinstance(items,list):
        for x in items:
            if isinstance(x,dict) and str(x.get("source_ref") or "").strip(): out.add(str(x["source_ref"]).strip())
            elif isinstance(x,str) and x.strip(): out.add(x.strip())
    return out


def evaluate(payload: dict[str,Any]) -> tuple[dict[str,int],dict[str,Any]]:
    ing=payload.get("screen_ingestion") if isinstance(payload.get("screen_ingestion"),dict) else {}
    pack=payload.get("story_pack") if isinstance(payload.get("story_pack"),dict) else {}
    ctx=payload.get("external_context") if isinstance(payload.get("external_context"),dict) else {}
    obs=[x for x in ing.get("visual_observation_inventory",[]) if isinstance(x,dict)]
    tokens=(pack.get("tokens_messages") or {}).get("tokens",[]) if isinstance(pack.get("tokens_messages"),dict) else []
    messages=(pack.get("tokens_messages") or {}).get("messages",[]) if isinstance(pack.get("tokens_messages"),dict) else []
    interaction_refs=refs_from((pack.get("interaction") or {}).get("source_observation_refs",[]) if isinstance(pack.get("interaction"),dict) else [])
    token_refs=refs_from(tokens)
    message_refs=refs_from(messages)
    sec_refs=refs_from((pack.get("security_privacy") or {}).get("source_observation_refs",[]) if isinstance(pack.get("security_privacy"),dict) else [])
    ra=pack.get("responsive_accessibility") if isinstance(pack.get("responsive_accessibility"),dict) else {}
    ra_refs=refs_from(ra.get("source_observation_refs",[]))
    pending=(pack.get("dependencies_risks") or {}).get("pending_decisions",[]) if isinstance(pack.get("dependencies_risks"),dict) else []
    pending_refs=refs_from(pending)

    missing=[]
    for x in obs:
        ref=str(x.get("source_ref") or "").strip(); typ=x.get("observation_type")
        destinations=set()
        if typ in TOKEN_TYPES: destinations |= interaction_refs | token_refs
        if typ in MESSAGE_TYPES: destinations |= message_refs | interaction_refs | sec_refs
        if typ in RESP_TYPES: destinations |= ra_refs | pending_refs
        if ref and ref not in destinations: missing.append(ref)

    registry_refs=set(str(x) for x in ctx.get("token_registry_refs",[]) if str(x).strip())
    false_registered=[]
    for t in tokens if isinstance(tokens,list) else []:
        if not isinstance(t,dict): continue
        if t.get("registered") is True or t.get("status")=="REGISTERED":
            rr=str(t.get("registry_ref") or "").strip()
            if not rr or rr not in registry_refs: false_registered.append(str(t.get("token_code") or t.get("source_ref") or "<token>"))

    exact_font=[]
    for x in obs:
        if x.get("observation_type")=="TYPOGRAPHY_APPEARANCE" and x.get("value_precision")=="EXACT_DECLARED" and x.get("observation_basis")!="DECLARED_SOURCE_METADATA":
            exact_font.append(str(x.get("source_ref")))

    shapes={(x.get("width_px"),x.get("height_px")) for x in ing.get("source_images",[]) if isinstance(x,dict)}
    single=len(shapes)<=1
    breakpoints=ra.get("breakpoints_supported") or []
    invented_breakpoints=1 if single and breakpoints and ctx.get("supported_breakpoints_confirmed") is not True else 0
    nonvisual_accessibility=0
    for key in ("keyboard_operable","aria_labels_present","focus_order_verified","error_announcement_verified"):
        if ra.get(key) is True and ctx.get("accessibility_baseline_confirmed") is not True:
            nonvisual_accessibility += 1

    checks={
      "v02_locked_input_required": 0 if ing.get("schema_version")=="screen-ingestion/v0.2" and ing.get("locked") is True else 1,
      "visual_observation_downstream_coverage": len(missing),
      "registered_token_requires_registry": len(false_registered),
      "exact_typography_requires_declared_metadata": len(exact_font),
      "single_viewport_breakpoint_not_invented": invented_breakpoints,
      "nonvisual_accessibility_not_invented": nonvisual_accessibility,
    }
    evidence={
      "visual_observation_count":len(obs),"covered_visual_observation_count":len(obs)-len(missing),
      "missing_source_refs":missing,"false_registered_tokens":false_registered,"exact_font_violations":exact_font,
      "single_viewport":single,"breakpoints_supported":breakpoints,"checks":checks,
    }
    return checks,evidence


def build(payload:Any, refs:list[str], input_path:str|None, input_sha:str)->dict[str,Any]:
    if not isinstance(payload,dict):
        return result_object(JUDGE,[],{"checks":{},"input_path":input_path},refs,[],["required_input_missing"],judge_version=VERSION,executor_identity="VISUAL_BRIDGE_VALIDATOR",command=" ".join(sys.argv))
    checks,evidence=evaluate(payload); evidence.update({"input_path":input_path,"input_sha256":input_sha})
    failed=[k for k,v in checks.items() if v]
    repairs=[failure(k,"$bridge",f"Repair visual evidence bridge until {k}=0 without inventing product facts.") for k in failed]
    return result_object(JUDGE,failed,evidence,refs,repairs,judge_version=VERSION,executor_identity="VISUAL_BRIDGE_VALIDATOR",command=" ".join(sys.argv))


def self_test()->int:
    root=Path(__file__).resolve().parent.parent
    good=load_json(root/'evals/fixtures/visual_bridge_positive.json')
    cases=[]
    def case(name,mutate,required):
        x=copy.deepcopy(good); mutate(x); out=build(x,[f"self-test://{name}"],None,"0"*64)
        cases.append({"case":name,"result":out['result'],"failed":out.get('failed_assertions') or [],"passed":required in set(out.get('failed_assertions') or [])})
    out=build(copy.deepcopy(good),["self-test://positive"],None,"0"*64)
    cases.append({"case":"positive","result":out['result'],"passed":out['result']=="PASS_WITH_EVIDENCE"})
    case("downstream_omission",lambda x:x['story_pack']['tokens_messages']['messages'].pop(),"visual_observation_downstream_coverage")
    case("false_registered_token",lambda x:(x['story_pack']['tokens_messages']['tokens'][0].update({'registered':True,'status':'REGISTERED'})),"registered_token_requires_registry")
    case("invented_breakpoint",lambda x:x['story_pack']['responsive_accessibility'].__setitem__('breakpoints_supported',['SMALL','LARGE']),"single_viewport_breakpoint_not_invented")
    case("invented_keyboard_claim",lambda x:x['story_pack']['responsive_accessibility'].__setitem__('keyboard_operable',True),"nonvisual_accessibility_not_invented")
    case("legacy_v01_not_bridge_eligible",lambda x:x['screen_ingestion'].__setitem__('schema_version','screen-ingestion/v0.1'),"v02_locked_input_required")
    ok=all(c['passed'] for c in cases)
    print(json.dumps({'self_test_pass':ok,'cases':cases},ensure_ascii=False,sort_keys=True)); return 0 if ok else 1


def main()->int:
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument('input',nargs='?',type=Path); ap.add_argument('--evidence-ref',action='append',default=[]); ap.add_argument('--self-test',action='store_true'); a=ap.parse_args()
    if a.self_test:return self_test()
    if a.input is None: raise ValidationInputError('input_required')
    return emit(build(load_json(a.input),a.evidence_ref or [f'file:{a.input}'],str(a.input),sha256_file(a.input)))
if __name__=='__main__': raise SystemExit(main_guard(JUDGE,main))
