#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parents[3]
ASSESS=ROOT/"sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
SELECT=ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
for p in (ASSESS,SELECT):
    if str(p) not in sys.path: sys.path.insert(0,str(p))

from evaluate_s26_learning_preflight import evaluate_learning_preflight
from evaluate_s26_profile_baseline import evaluate as evaluate_s26
from profile_assessment_v2 import assess_profile_v2
from capability_selector_v3 import compose_capabilities_v3

def build_from_resolved(
    slug:str,
    structural:dict[str,Any],
    learning:dict[str,Any],
    assessment_payload:dict[str,Any],
    capability_catalog:list[dict[str,Any]],
    capability_policy:dict[str,Any],
    method_registry:dict[str,Any],
    precondition_state:dict[str,Any],
)->dict[str,Any]:
    normalized=dict(assessment_payload)
    decision=structural.get("decision")
    normalized["structural_status"]="PASS" if decision=="NO_UPDATE_REQUIRED" else ("FAIL" if decision=="UPDATE_REQUIRED" else "UNKNOWN")
    normalized.setdefault("architecture_status","PASS")
    assessment=assess_profile_v2(normalized)

    selection_context={
      **(normalized.get("signals") if isinstance(normalized.get("signals"),dict) else {}),
      "profile_gaps":normalized.get("profile_gaps",[]),
      "budget":normalized.get("budget",{}),
      "selection_cycle":0,
      "allow_experimental_methods":bool(normalized.get("allow_experimental_methods",False)),
    }
    selection=compose_capabilities_v3(selection_context,capability_catalog,capability_policy,method_registry,precondition_state)

    blockers=[]
    if learning.get("status")!="PASS": blockers.append("BLOCKED_LEARNING_PREFLIGHT")
    if decision=="BLOCKED_AUTHORITY_REQUIRED": blockers.append("BLOCKED_AUTHORITY_REQUIRED")
    if assessment["assessment_status"]!="EVIDENCE_SUFFICIENT": blockers.append("PROFILE_ASSESSMENT_NEEDS_MORE_EVIDENCE")
    if selection["fallback_state"] in {"CONTRADICTORY","CAPABILITY_FAILURE"}: blockers.append("BLOCKED_SELECTOR_UNRESOLVED")

    active_precondition_rejections=[
      r for r in selection["rejected_methods"]
      if r.get("reason") in {"PRECONDITION_UNKNOWN","PRECONDITION_FAIL"}
    ]
    if active_precondition_rejections and not selection["selected_methods"]:
        blockers.append("METHOD_PRECONDITIONS_UNRESOLVED")

    mode=assessment.get("evolution_mode")
    change_needed=mode not in (None,"NO_CHANGE")
    candidate_allowed=bool(change_needed and not blockers)
    return {
      "schema":"PROFILE_EVOLUTION_PLAN_V2",
      "operation_code":"ACTUALIZACION_PERFIL_LF",
      "profile_slug":slug,
      "structural_baseline":structural,
      "learning_preflight":learning,
      "profile_assessment":assessment,
      "competency_vector":assessment["competency_vector"],
      "evolution_mode":mode,
      "selection":selection,
      "adaptive_loop":{
        "enabled":candidate_allowed,
        "cycle":["SELECT","VERIFY_PRECONDITIONS","EXECUTE","OBSERVE","EVALUATE","REPLAN_OR_STOP"],
        "replan_allowed":True,
        "persistent_learning_authorized":False,
        "replan_history_required":True,
      },
      "candidate_materialization_allowed":candidate_allowed,
      "candidate_execution_required_before_expertise_claim":True,
      "expert_behavior_benchmark_required":True,
      "architecture_control_benchmark_is_cutover_evidence":False,
      "candidate_boundary":"REVERSIBLE_NON_AUTHORITY",
      "profile_source_write_allowed":False,
      "write_requires_admission":True,
      "blocking_codes":sorted(set(blockers)),
      "next_gate":(
        "ADAPTIVE_EVOLUTION_LOOP" if candidate_allowed
        else "NO_CHANGE" if mode=="NO_CHANGE" and not blockers
        else "TARGETED_EVIDENCE_ACQUISITION" if "PROFILE_ASSESSMENT_NEEDS_MORE_EVIDENCE" in blockers or "METHOD_PRECONDITIONS_UNRESOLVED" in blockers
        else "RETURN_TO_EVIDENCE_OR_AUTHORITY"
      ),
      "automatic_runtime_activation":False,
      "automatic_production_activation":False,
    }

def build_evolution_plan_v2(repo:Path,slug:str,preflight_payload:object,assessment_payload:dict[str,Any],
                            capability_catalog:list[dict[str,Any]],capability_policy:dict[str,Any],
                            method_registry:dict[str,Any],precondition_state:dict[str,Any],current_revision:str|None=None)->dict[str,Any]:
    structural=evaluate_s26(repo,slug)
    learning=evaluate_learning_preflight(preflight_payload,slug,repo_root=repo,current_revision=current_revision)
    return build_from_resolved(slug,structural,learning,assessment_payload,capability_catalog,capability_policy,method_registry,precondition_state)

def main()->int:
    if len(sys.argv)!=8:
        print("usage: plan_profile_evolution_v2.py <slug> <preflight.json> <assessment.json> <capability_catalog.json> <capability_policy.json> <method_registry.json> <precondition_state.json>",file=sys.stderr)
        return 2
    slug=sys.argv[1]
    payloads=[json.loads(Path(p).read_text(encoding="utf-8")) for p in sys.argv[2:]]
    out=build_evolution_plan_v2(ROOT,slug,*payloads)
    print(json.dumps(out,indent=2,sort_keys=True))
    return 0 if not out["blocking_codes"] else 3

if __name__=="__main__": raise SystemExit(main())
