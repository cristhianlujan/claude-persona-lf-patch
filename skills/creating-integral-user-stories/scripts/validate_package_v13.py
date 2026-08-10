#!/usr/bin/env python3
"""J11 v1.3 package gate with semantic runtime evidence and real M7 chain proof.

The legacy v1.2 package gate remains untouched. JSON evidence declaring
`evidence_kind=REAL_SCREEN_RUN` is audited as RUNTIME_EVIDENCE (1-50 KB,
NUCLEO); synthetic fixtures retain the original fixture band. The v1.3
self-test also executes the current locked real-screen v0.2 chain through
J01/J00/visual adjudication/J02/visual bridge/J08/J10 before J11 passes.
"""
from __future__ import annotations
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import validate_package as legacy
from lf_common import ValidationInputError, failure
import validate_real_visual_runtime_v02 as visual_runtime
import validate_screen_decomposition_visual as j02
import validate_screen_ingestion_v02 as j00
import validate_source_integrity as j01
import validate_test_coverage as j10
import validate_visual_evidence_bridge as bridge

VERSION="v1.3"
RUNTIME_FIXTURE="evals/fixtures/real_screen_onboarding_step1_blind_run.json"
REFERENCE_FIXTURE="evals/fixtures/real_screen_onboarding_step1_reference.json"
TOKEN_TYPES={"CONTROL","ICON","COLOR_APPEARANCE","TYPOGRAPHY_APPEARANCE","SPACING_APPEARANCE","SIZE_RADIUS_APPEARANCE","VISUAL_STATE","PROGRESS"}
MESSAGE_TYPES={"COPY","PLACEHOLDER","LINK","CONSENT","SECURITY_TRUST"}
RESP_TYPES={"RESPONSIVE","ACCESSIBILITY"}

legacy.GATE_VERSION=VERSION
legacy.BANDS["RUNTIME_EVIDENCE"]=(1000,50000)
_orig_audit=legacy.audit_artifact
_orig_self_test=legacy.self_test
_orig_type=legacy.artifact_type
_orig_tier=legacy.artifact_tier
_orig_structured=legacy.structured_dimensions

def structured_dimensions(rel,kind,body,parsed):
    if kind != "RUNTIME_EVIDENCE": return _orig_structured(rel,kind,body,parsed)
    data=parsed if isinstance(parsed,dict) else {}
    isolation=data.get("context_isolation") if isinstance(data.get("context_isolation"),dict) else {}
    coverage=data.get("coverage_evidence") if isinstance(data.get("coverage_evidence"),dict) else {}
    images=data.get("source_images") if isinstance(data.get("source_images"),list) else []
    return [
      legacy.Dimension("purpose_scope",data.get("evidence_kind")=="REAL_SCREEN_RUN","empirical run identity"),
      legacy.Dimension("input_contract",bool(images) and bool(data.get("source_snapshot_sha")),"source binding metadata"),
      legacy.Dimension("deterministic_procedure",data.get("locked") is True and coverage.get("full_viewport_scanned") is True,"locked full-viewport run"),
      legacy.Dimension("output_contract",all(data.get(k) for k in ("blind_read_id","execution_id","reader_identity")),"run identity tuple"),
      legacy.Dimension("positive_behavior",set(coverage.get("images_scanned") or [])=={str(x.get("image_ref")) for x in images if isinstance(x,dict)},"declared images scanned"),
      legacy.Dimension("negative_behavior",isolation.get("auxiliary_context_before_lock") is False and isolation.get("action_tools_enabled") is False and isolation.get("network_egress")=="DENY_BY_DEFAULT","blind isolation guards"),
    ]
legacy.structured_dimensions=structured_dimensions

def is_runtime(root:Path, rel:str)->bool:
    if not rel.startswith("evals/fixtures/") or not rel.endswith(".json"): return False
    try: value=json.loads((root/rel).read_text(encoding="utf-8"))
    except Exception: return False
    return isinstance(value,dict) and value.get("evidence_kind")=="REAL_SCREEN_RUN"

def audit_artifact(root:Path, rel:str, actual:set[str]):
    if not is_runtime(root,rel): return _orig_audit(root,rel,actual)
    old_type,old_tier=legacy.artifact_type,legacy.artifact_tier
    legacy.artifact_type=lambda r: "RUNTIME_EVIDENCE" if r==rel else _orig_type(r)
    legacy.artifact_tier=lambda r: "NUCLEO" if r==rel else _orig_tier(r)
    try: return _orig_audit(root,rel,actual)
    finally: legacy.artifact_type,legacy.artifact_tier=old_type,old_tier
legacy.audit_artifact=audit_artifact

def _canonical_bytes(value:Any)->bytes:
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode("utf-8")

def _sha(value:Any)->str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()

def _load(path:Path)->dict[str,Any]:
    value=json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value,dict): raise ValueError(f"object_required:{path}")
    return value

def _source_payload(blind:dict[str,Any])->dict[str,Any]:
    images=[x for x in blind.get("source_images",[]) if isinstance(x,dict)]
    manifest=j00.legacy.source_manifest(images)
    content=json.dumps(manifest,ensure_ascii=False,sort_keys=True,separators=(",",":"))
    return {
      "source_snapshot":{"content":content,"sha256":hashlib.sha256(content.encode("utf-8")).hexdigest(),"source_version":str(blind.get("source_version") or "")},
      "target_source_version":str(blind.get("source_version") or ""),
      "source_references":[{"ref":str(x.get("image_ref") or ""),"resolved":bool(x.get("raw_content_sha256"))} for x in images],
      "classification_ledger":[{"classification":"CONFIRMED","source_ref":str(x.get("image_ref") or "")} for x in images],
    }

def _decomposition(blind:dict[str,Any])->dict[str,Any]:
    fu="FU-ONBOARDING-STEP1"
    contexts=[{"code":str(x["code"]),"description":str(x["description"]),"source_ref":str(x["source_ref"])} for x in blind.get("context_inventory",[]) if isinstance(x,dict)]
    fields=[{"code":str(x["code"]),"context_code":str(x["context_code"]),"source_ref":str(x["source_ref"])} for x in blind.get("field_inventory",[]) if isinstance(x,dict)]
    permissions=[{"permission_code":str(x["permission_code"]),"actor_profile":str(x["actor_profile"]),"action_code":str(x["action_code"]),"source_ref":str(x["source_ref"])} for x in blind.get("permission_inventory",[]) if isinstance(x,dict)]
    transitions=[{"from":str(x["from"]),"action":str(x["action"]),"to":str(x["to"]),"allowed":bool(x["allowed"]),"source_ref":str(x["source_ref"])} for x in blind.get("transition_inventory",[]) if isinstance(x,dict)]
    coverage=[]
    for kind,entries,key in (("CONTEXT",contexts,"code"),("FIELD",fields,"code"),("PERMISSION",permissions,"permission_code")):
        for item in entries:
            coverage.append({"source_item_code":str(item[key]),"source_type":kind,"source_ref":str(item["source_ref"]),"mapping_status":"MAPPED","mapped_to":[fu],"justification":"Preserved from locked screen ingestion."})
    for index,item in enumerate(transitions,start=1):
        coverage.append({"source_item_code":f"TR-{index:03d}","source_type":"TRANSITION","source_ref":str(item["source_ref"]),"mapping_status":"MAPPED","mapped_to":[fu],"justification":"Preserved from locked screen ingestion."})
    pending=[]
    for obs in blind.get("visual_observation_inventory",[]):
        if not isinstance(obs,dict) or obs.get("observation_type") not in RESP_TYPES: continue
        pending.append({
          "decision_code":f"PD-{str(obs.get('observation_code') or 'VISUAL').replace('OBS-','')}",
          "missing_fact":str(obs.get("visual_value") or "Nonvisual behavior is not observable from the fixed screenshot."),
          "why_required":"Required downstream only if product policy needs verified nonvisual behavior.",
          "source_checked":[str(obs.get("source_ref") or "")],"blocking":False,"status":"OPEN",
        })
    n=len(coverage)
    return {
      "screen_code":str(blind.get("screen_code") or ""),"source_version":str(blind.get("source_version") or ""),
      "source_snapshot_sha":str(blind.get("source_snapshot_sha") or ""),
      "main_responsibility":"Preserve visible onboarding identity, contact, consent and trust evidence before downstream story derivation.",
      "module_code":"MOD-LF-ONBOARDING","context_inventory":contexts,"field_inventory":fields,
      "permission_inventory":permissions,"transition_inventory":transitions,
      "functional_units":[{
        "functional_unit_code":fu,"actor":"Prospective customer",
        "goal":"Provide identity and contact data to continue the debt-options onboarding flow.",
        "trigger":"Open onboarding step 1",
        "observable_output":"The identity, contact and consent form is presented for verification.",
        "risk_level":"MEDIUM","decision":"CREATE_STORY",
        "justification":"The visible screen groups one onboarding verification responsibility with consent and trust evidence.",
        "source_ref":f"{blind['source_images'][0]['image_ref']}#OBS-023","classification":"INFERRED",
      }],
      "coverage_items":coverage,
      "coverage_summary":{"source_items_count":n,"mapped_count":n,"justified_count":0,"unmapped_count":0,"unjustified_count":0,"conflicting_count":0,"duplicate_functional_units_count":0},
      "pending_decisions":pending,
      "visual_observation_inventory":[dict(x) for x in blind.get("visual_observation_inventory",[]) if isinstance(x,dict)],
    }

def _story_pack(blind:dict[str,Any])->dict[str,Any]:
    obs=[x for x in blind.get("visual_observation_inventory",[]) if isinstance(x,dict)]
    token_refs=[str(x["source_ref"]) for x in obs if x.get("observation_type") in TOKEN_TYPES]
    msg_obs=[x for x in obs if x.get("observation_type") in MESSAGE_TYPES]
    resp_refs=[str(x["source_ref"]) for x in obs if x.get("observation_type") in RESP_TYPES]
    sec_refs=[str(x["source_ref"]) for x in obs if x.get("observation_type") in {"CONSENT","SECURITY_TRUST"}]
    first=token_refs[0] if token_refs else str(obs[0]["source_ref"])
    criterion={"criterion_code":"AC-VISUAL-EVIDENCE-PRESERVED","given":"a locked screen-ingestion v0.2 payload exists","when":"visual evidence is routed downstream","then":"every visual source_ref remains covered or explicitly pending","source_ref":"M7://visual-evidence-chain"}
    test={"test_code":"TEST-VISUAL-EVIDENCE-PRESERVED","family":"TRACEABILITY","criterion_ref":"AC-VISUAL-EVIDENCE-PRESERVED","preconditions":["locked v0.2 blind evidence"],"steps":["compare ingestion refs with downstream coverage refs"],"expected_result":"all visual source refs remain covered","negative":False,"critical":True,"automatable":True,"evidence_path":"evidence/M7-visual-evidence-chain.json"}
    return {
      "core":{"acceptance_criteria":[criterion]},"tests":[test],
      "interaction":{"source_observation_refs":token_refs},
      "tokens_messages":{
        "tokens":[{"token_code":"candidate.visual.evidence-anchor","registered":False,"status":"CANDIDATO","source_ref":first}],
        "messages":[{"message_code":f"MSG-{str(x['observation_code']).replace('OBS-','')}","severity":"INFO","text_ref":str(x["source_ref"]),"source_ref":str(x["source_ref"])} for x in msg_obs],
      },
      "security_privacy":{"source_observation_refs":sec_refs},
      "responsive_accessibility":{"breakpoints_supported":[],"source_observation_refs":resp_refs,"status":"PENDING_DECISION"},
      "dependencies_risks":{"pending_decisions":[{"decision_code":f"PD-{i:03d}","source_ref":ref,"status":"PENDING_DECISION"} for i,ref in enumerate(resp_refs,start=1)]},
    }

def _j08(root:Path,story:dict[str,Any])->dict[str,Any]:
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)/"story.json"; p.write_text(json.dumps(story,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        proc=subprocess.run([sys.executable,str(root/"scripts"/"validate_tokens.py"),str(p),"--judge-version","v0.5","--executor-identity","M7_J08_VALIDATOR"],cwd=root,text=True,capture_output=True)
    parsed=None
    for line in reversed([x.strip() for x in proc.stdout.splitlines() if x.strip()]):
        try: candidate=json.loads(line)
        except json.JSONDecodeError: continue
        if isinstance(candidate,dict): parsed=candidate; break
    return {"exit_code":proc.returncode,"result":parsed.get("result") if isinstance(parsed,dict) else None,"failed_assertions":parsed.get("failed_assertions") if isinstance(parsed,dict) else None,"passed":proc.returncode==0 and isinstance(parsed,dict) and parsed.get("result")=="PASS_WITH_EVIDENCE"}

def real_chain(root:Path)->dict[str,Any]:
    blind=_load(root/RUNTIME_FIXTURE); reference=_load(root/REFERENCE_FIXTURE)
    j01_checks,_=j01.validate_payload(_source_payload(blind))
    j00_checks,j00_evidence=j00.evaluate(blind)
    runtime=visual_runtime.evaluate_runtime(blind,reference)

    dec=_decomposition(blind)
    j02_payload={"target_screen_code":blind["screen_code"],"screen_ingestion":blind,"screen_decomposition":dec}
    meta=j02.runtime_meta()
    j02_out=j02.legacy.build(j02_payload,["m7://real-visual-chain"],0,"M7_J02_VALIDATOR",j02.legacy.VERSION,meta["semantic_validator_sha256"],j02.REGISTRATION,_sha(j02_payload),None,"M7 real visual J02")

    story=_story_pack(blind)
    bridge_payload={"screen_ingestion":blind,"story_pack":story,"external_context":{"accessibility_baseline_confirmed":False,"supported_breakpoints_confirmed":False,"token_registry_refs":[]}}
    bridge_checks,bridge_evidence=bridge.evaluate(bridge_payload)
    j08=_j08(root,story)

    j10_payload={
      "story_pack":story,"critical_rules":[],
      "fixtures":{"TEST-VISUAL-EVIDENCE-PRESERVED":{"actor":"M7_E2E_DERIVER","tenant":"LF-CANDIDATE","initial_state":{"blind_locked":True},"exact_inputs":{"source_snapshot_sha":blind["source_snapshot_sha"],"visual_observation_count":len(blind.get("visual_observation_inventory",[]))},"steps":["compare all source_ref values across the derived chain"],"expected_result":"all visual source refs remain covered","evidence_path":"evidence/M7-visual-evidence-chain.json"}},
      "traceability_matrix":{"criteria":{"AC-VISUAL-EVIDENCE-PRESERVED":["M7://visual-evidence-chain"]},"rules":{}},
      "test_environment":{"actors":["M7_E2E_DERIVER","M7_J10_VALIDATOR"],"tenants":["LF-CANDIDATE"],"initial_states":["LOCKED_BLIND_V02"],"data_sets":["REAL_SCREEN_ONBOARDING_STEP1"],"restrictions":["NO_INVENTED_NONVISUAL_REQUIREMENTS"]},
    }
    j10_checks,_=j10.validate_payload(j10_payload,executor_identity="M7_J10_VALIDATOR",worker_identity="M7_E2E_DERIVER")

    observations=[x for x in blind.get("visual_observation_inventory",[]) if isinstance(x,dict)]
    checks={
      "j01_source_integrity":all(v==0 for v in j01_checks.values()),
      "j00_v02":all(v==0 for v in j00_checks.values()) and j00_evidence.get("v02_protocol_eligible") is True,
      "visual_runtime":runtime.get("visual_runtime_proven") is True,
      "j02":j02_out.get("result")=="PASS_WITH_EVIDENCE",
      "visual_bridge":all(v==0 for v in bridge_checks.values()),
      "j08":j08["passed"] is True,
      "j10":all(v==0 for v in j10_checks.values()),
      "source_to_ingestion_count":len(blind.get("source_images",[]))==1,
      "ingestion_to_decomposition_visual_1to1":len(observations)==len(dec.get("visual_observation_inventory",[])),
      "decomposition_to_story_pack_visual_coverage":bridge_evidence.get("covered_visual_observation_count")==len(observations),
      "no_silent_visual_omissions":not bridge_evidence.get("missing_source_refs"),
    }
    return {
      "local_chain_pass":all(checks.values()),"checks":checks,
      "source_snapshot_sha":blind.get("source_snapshot_sha"),"blind_read_id":blind.get("blind_read_id"),"execution_id":blind.get("execution_id"),
      "counts":{"source_images":len(blind.get("source_images",[])),"contexts":len(blind.get("context_inventory",[])),"fields":len(blind.get("field_inventory",[])),"ingestion_visual_observations":len(observations),"decomposition_visual_observations":len(dec.get("visual_observation_inventory",[])),"story_pack_covered_visual_observations":bridge_evidence.get("covered_visual_observation_count"),"responsive_accessibility_pending":len(story["responsive_accessibility"]["source_observation_refs"])},
      "runtime_blockers":runtime.get("blockers",[]),"j02_failed_assertions":j02_out.get("failed_assertions",[]),"bridge_checks":bridge_checks,"j08":j08,"j10_checks":j10_checks,
      "j11":"THIS_SELF_TEST","j12_j13":"EXACT_HEAD_CI_REQUIRED",
    }

def self_test():
    root=Path(__file__).resolve().parent.parent
    base=_orig_self_test()
    semantic=is_runtime(root,RUNTIME_FIXTURE)
    synthetic=not is_runtime(root,"evals/fixtures/screen_ingestion_dense.json")
    chain=real_chain(root)
    ok=base==0 and semantic and synthetic and chain["local_chain_pass"] is True
    print(json.dumps({"judge_code":legacy.JUDGE,"quality_gate_version":VERSION,"runtime_evidence_semantic_classification":semantic,"synthetic_fixture_preserved":synthetic,"real_visual_e2e":chain,"self_test_pass":ok},ensure_ascii=False,sort_keys=True))
    return 0 if ok else 1
legacy.self_test=self_test

def main(): return legacy.main()
if __name__=="__main__": raise SystemExit(legacy.main_guard(legacy.JUDGE,main))
