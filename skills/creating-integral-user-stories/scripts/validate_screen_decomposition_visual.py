#!/usr/bin/env python3
"""Visual-evidence passthrough wrapper for J02 v0.8.

Preserves the registered v0.8 decomposition semantics and adds:
- lossless screen-ingestion/v0.2 observation coverage;
- fail-closed epistemic invariants for CONFIRMED functional units.
"""
from __future__ import annotations
import copy
import hashlib
from pathlib import Path
from typing import Any
import validate_screen_decomposition_v08 as legacy

REGISTRATION="candidate://creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION_VISUAL"
EXTRA="visual_observation_coverage"
EPISTEMIC="confirmed_epistemic_invariants"
INHERITED="confirmed_inherited_inference"
_orig_semantic=legacy.semantic
_orig_self_test=legacy.self_test
legacy.REGISTRATION=REGISTRATION
legacy.ASSERTIONS=(*legacy.ASSERTIONS,EXTRA,EPISTEMIC,INHERITED)

def runtime_meta():
    path=Path(__file__).resolve(); raw=path.read_bytes()
    return {"semantic_validator_path":str(path),"semantic_validator_sha256":hashlib.sha256(raw).hexdigest(),"semantic_validator_git_blob_sha1":hashlib.sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest(),"semantic_validator_bytes":len(raw)}
legacy.runtime_meta=runtime_meta

def epistemic_invariant_violations(ingestion:dict[str,Any],dec:dict[str,Any]):
    direct_refs=set()
    for key in ("context_inventory","field_inventory","permission_inventory","transition_inventory"):
        for item in ingestion.get(key,[]) or []:
            if isinstance(item,dict) and str(item.get("source_ref") or "").strip():
                direct_refs.add(str(item["source_ref"]).strip())
    visual_states={}
    for item in ingestion.get("visual_observation_inventory",[]) or []:
        if not isinstance(item,dict):
            continue
        ref=str(item.get("source_ref") or "").strip()
        state=str(item.get("observability") or "").strip()
        if ref:
            visual_states.setdefault(ref,set()).add(state)
    uncertainty_refs={str(x.get("source_ref") or "").strip() for x in ingestion.get("uncertainties",[]) or [] if isinstance(x,dict) and str(x.get("source_ref") or "").strip()}
    violations=[]; inherited=[]
    for unit in dec.get("functional_units",[]) or []:
        if not isinstance(unit,dict) or unit.get("classification")!="CONFIRMED":
            continue
        code=str(unit.get("functional_unit_code") or "")
        ref=str(unit.get("source_ref") or "").strip()
        reasons=[]
        if not ref or (ref not in direct_refs and ref not in visual_states):
            reasons.append("SOURCE_EVIDENCE_UNRESOLVED")
        if ref in uncertainty_refs:
            reasons.append("UNRESOLVED_SOURCE_UNCERTAINTY")
        states=visual_states.get(ref,set())
        if states and states!={"OBSERVED"}:
            reasons.append("NON_OBSERVED_SOURCE_PROMOTED")
            inherited.append(ref)
        if len(states)>1:
            reasons.append("CONFLICTING_EPISTEMIC_STATES")
        if reasons:
            violations.append({"functional_unit_code":code,"source_ref":ref,"reasons":sorted(set(reasons))})
    return violations,sorted(set(inherited))

def semantic(target:str,ingestion:dict[str,Any],dec:dict[str,Any]):
    checks,evidence=_orig_semantic(target,ingestion,dec)
    missing=[]
    if ingestion.get("schema_version")=="screen-ingestion/v0.2":
        source={(str(x.get("observation_code") or ""),str(x.get("source_ref") or "")) for x in ingestion.get("visual_observation_inventory",[]) if isinstance(x,dict)}
        dest={(str(x.get("observation_code") or ""),str(x.get("source_ref") or "")) for x in dec.get("visual_observation_inventory",[]) if isinstance(x,dict)}
        missing=sorted(source-dest)
    violations,inherited=epistemic_invariant_violations(ingestion,dec)
    checks[EXTRA]=len(missing)
    checks[EPISTEMIC]=len(violations)
    checks[INHERITED]=len(inherited)
    evidence["missing_visual_observations"]=[list(x) for x in missing]
    evidence["visual_observation_passthrough_count"]=len(dec.get("visual_observation_inventory") or [])
    evidence["confirmed_epistemic_violations"]=violations
    evidence["confirmed_inherited_inference_refs"]=inherited
    evidence["epistemic_policy"]={
        "confirmed_requires_resolvable_locked_ingestion_evidence":True,
        "confirmed_with_source_uncertainty":"BLOCKED",
        "confirmed_from_inferred_or_not_observable":"BLOCKED",
        "automatic_downgrade_or_promotion":False,
    }
    evidence["checks"]=checks
    return checks,evidence
legacy.semantic=semantic

def self_test():
    if _orig_self_test()!=0:
        return 1
    root=Path(__file__).resolve().parent.parent
    payload=legacy.load_json(root/"evals"/"fixtures"/"j02_external_positive.json")
    inferred=copy.deepcopy(payload)
    inferred["screen_decomposition"]["functional_units"][0]["source_ref"]="IMG-001#RESPONSIVE-NOT-OBSERVABLE"
    inferred_checks,_=semantic(inferred["target_screen_code"],inferred["screen_ingestion"],inferred["screen_decomposition"])
    uncertain=copy.deepcopy(payload)
    uncertain["screen_ingestion"]["uncertainties"].append({"uncertainty_code":"UNC-EPISTEMIC-SELFTEST","critical":False,"description":"Source requires independent confirmation","source_ref":"IMG-001#REG-SEARCH"})
    uncertain_checks,_=semantic(uncertain["target_screen_code"],uncertain["screen_ingestion"],uncertain["screen_decomposition"])
    return 0 if inferred_checks[INHERITED]>0 and inferred_checks[EPISTEMIC]>0 and uncertain_checks[EPISTEMIC]>0 else 1
legacy.self_test=self_test

def main():
    return legacy.main()
if __name__=="__main__":
    raise SystemExit(legacy.main_guard(legacy.JUDGE,main))
