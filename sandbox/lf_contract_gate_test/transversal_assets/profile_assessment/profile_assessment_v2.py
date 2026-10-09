from __future__ import annotations

from collections import defaultdict
from statistics import mean
from typing import Any

MATURITY_STATES = ["UNDETERMINED","GENERIC","SPECIALIZED","ADAPTIVE","EXPERT","EVIDENCE_OPTIMIZED"]
EVOLUTION_MODES = {"NO_CHANGE","PATCH","SPECIALIZE","ADAPT","REARCHITECT","OPTIMIZE"}

DEFAULT_POLICY = {
    "solved_threshold": 0.8,
    "min_cases_at_difficulty": 2,
    "min_verified_observations": 6,
    "generic": {
        "domain_quality_max_exclusive": 0.7
    },
    "specialized": {
        "domain_quality_min": 0.7,
        "max_difficulty_min": 2,
        "preservation_min": 0.95
    },
    "adaptive": {
        "domain_quality_min": 0.75,
        "max_difficulty_min": 3,
        "robustness_min": 0.7,
        "adaptation_min": 0.7,
        "preservation_min": 0.97
    },
    "expert": {
        "domain_quality_min": 0.85,
        "max_difficulty_min": 4,
        "robustness_min": 0.8,
        "adaptation_min": 0.8,
        "transfer_min": 0.75,
        "preservation_min": 0.98,
        "critical_failures_max": 0
    },
    "evidence_optimized": {
        "expert_required": true,
        "min_generations": 3,
        "causal_confidence_min": 0.75
    }
}

def _is_num(v: Any) -> bool:
    return isinstance(v,(int,float)) and not isinstance(v,bool)

def _verified(o: Any) -> bool:
    if not isinstance(o,dict):
        return False
    required=("task_ref","task_family","difficulty","score","verification_state","output_receipt_ref","evaluator_receipt_ref","evidence_refs")
    if any(o.get(k) in (None,"",[],{}) for k in required):
        return False
    if o.get("verification_state")!="VERIFIED":
        return False
    if not isinstance(o.get("evidence_refs"),list) or not o["evidence_refs"]:
        return False
    if not _is_num(o.get("difficulty")) or not (1 <= float(o["difficulty"]) <= 5):
        return False
    if not _is_num(o.get("score")) or not (0 <= float(o["score"]) <= 1):
        return False
    return True

def _weighted_quality(obs: list[dict[str,Any]]) -> float | None:
    if not obs:
        return None
    weights=[max(1.0,float(o["difficulty"])) for o in obs]
    return sum(float(o["score"])*w for o,w in zip(obs,weights))/sum(weights)

def _subset_mean(obs: list[dict[str,Any]], flag: str) -> float | None:
    xs=[float(o["score"]) for o in obs if o.get(flag) is True]
    return mean(xs) if xs else None

def _robustness(obs: list[dict[str,Any]]) -> float | None:
    groups: dict[str,list[float]]=defaultdict(list)
    for o in obs:
        g=o.get("repeat_group")
        if isinstance(g,str) and g:
            groups[g].append(float(o["score"]))
    group_scores=[mean(v) for v in groups.values() if len(v)>=2]
    return mean(group_scores) if group_scores else None

def _max_difficulty(obs: list[dict[str,Any]], threshold: float, min_cases: int) -> int | None:
    solved=0
    for d in range(1,6):
        xs=[float(o["score"]) for o in obs if int(o["difficulty"])==d]
        if len(xs)>=min_cases and mean(xs)>=threshold:
            solved=d
    return solved or None

def _efficiency(obs: list[dict[str,Any]]) -> tuple[float | None,str]:
    xs=[]
    for o in obs:
        ratio=o.get("cost_budget_ratio")
        if _is_num(ratio) and ratio>=0:
            xs.append(max(0.0,1.0-float(ratio)))
    return (mean(xs),"OBSERVED") if xs else (None,"NOT_OBSERVED")

def _critical_failures(obs: list[dict[str,Any]], solved_threshold: float) -> int:
    return sum(1 for o in obs if o.get("critical") is True and float(o["score"]) < solved_threshold)

def _merge_policy(payload: dict[str,Any]) -> dict[str,Any]:
    p=dict(DEFAULT_POLICY)
    supplied=payload.get("assessment_policy")
    if isinstance(supplied,dict):
        for k,v in supplied.items():
            if k in p:
                if isinstance(p[k],dict) and isinstance(v,dict):
                    p[k]={**p[k],**v}
                else:
                    p[k]=v
    return p

def _ge(v: float | int | None, threshold: float | int) -> bool:
    return v is not None and float(v)>=float(threshold)

def derive_maturity(vector: dict[str,Any], policy: dict[str,Any]) -> str:
    if vector["verified_observation_count"] < int(policy["min_verified_observations"]):
        return "UNDETERMINED"
    q=vector["domain_quality"]
    if q is None:
        return "UNDETERMINED"

    expert=policy["expert"]
    expert_ok=(
        _ge(q,expert["domain_quality_min"])
        and _ge(vector["max_difficulty_solved"],expert["max_difficulty_min"])
        and _ge(vector["robustness"],expert["robustness_min"])
        and _ge(vector["adaptation"],expert["adaptation_min"])
        and _ge(vector["transfer"],expert["transfer_min"])
        and _ge(vector["preservation"],expert["preservation_min"])
        and vector["critical_failures"]<=expert["critical_failures_max"]
    )
    optimized=policy["evidence_optimized"]
    if expert_ok and vector["longitudinal_evidence"]["verified_generations"]>=optimized["min_generations"] and _ge(vector["causal_confidence"],optimized["causal_confidence_min"]):
        return "EVIDENCE_OPTIMIZED"
    if expert_ok:
        return "EXPERT"

    adaptive=policy["adaptive"]
    if (
        _ge(q,adaptive["domain_quality_min"])
        and _ge(vector["max_difficulty_solved"],adaptive["max_difficulty_min"])
        and _ge(vector["robustness"],adaptive["robustness_min"])
        and _ge(vector["adaptation"],adaptive["adaptation_min"])
        and _ge(vector["preservation"],adaptive["preservation_min"])
    ):
        return "ADAPTIVE"

    specialized=policy["specialized"]
    if (
        _ge(q,specialized["domain_quality_min"])
        and _ge(vector["max_difficulty_solved"],specialized["max_difficulty_min"])
        and _ge(vector["preservation"],specialized["preservation_min"])
    ):
        return "SPECIALIZED"
    return "GENERIC"

def _mode(payload: dict[str,Any], maturity: str, vector: dict[str,Any]) -> tuple[str|None,list[str]]:
    structural=payload.get("structural_status","UNKNOWN")
    architecture=payload.get("architecture_status","UNKNOWN")
    if architecture=="FAIL":
        return "REARCHITECT",[]
    if structural=="FAIL":
        return "PATCH",[]
    if structural!="PASS" or architecture!="PASS":
        return None,["structural_compatibility" if structural!="PASS" else "architecture_fit"]
    if maturity=="UNDETERMINED":
        return None,["verified_competency_observations"]
    if maturity=="GENERIC":
        return "SPECIALIZE",[]
    if maturity=="SPECIALIZED":
        return "ADAPT",[]
    if maturity=="ADAPTIVE":
        return "OPTIMIZE",[]
    if maturity=="EXPERT":
        return "OPTIMIZE",[]
    if maturity=="EVIDENCE_OPTIMIZED":
        return "NO_CHANGE",[]
    return None,["maturity"]

def assess_profile_v2(payload: dict[str,Any]) -> dict[str,Any]:
    if not isinstance(payload,dict):
        raise ValueError("PROFILE_ASSESSMENT_INPUT_INVALID")
    observations=payload.get("competency_observations")
    if not isinstance(observations,list):
        raise ValueError("COMPETENCY_OBSERVATIONS_REQUIRED")
    policy=_merge_policy(payload)
    verified=[o for o in observations if _verified(o)]
    invalid_count=len(observations)-len(verified)
    q=_weighted_quality(verified)
    solved=_max_difficulty(verified,float(policy["solved_threshold"]),int(policy["min_cases_at_difficulty"]))
    robust=_robustness(verified)
    adaptation=_subset_mean(verified,"adaptation_case")
    transfer=_subset_mean(verified,"transfer_case")
    preservation=_subset_mean(verified,"preservation_case")
    efficiency,eff_status=_efficiency(verified)
    generations={o.get("generation") for o in verified if isinstance(o.get("generation"),int) and o["generation"]>=1}
    causal=payload.get("causal_attribution",{})
    causal_conf=float(causal["confidence"]) if isinstance(causal,dict) and _is_num(causal.get("confidence")) and causal.get("verification_state")=="VERIFIED" else None
    vector={
        "schema":"PROFILE_COMPETENCY_VECTOR_V1",
        "verified_observation_count":len(verified),
        "invalid_or_unverified_observation_count":invalid_count,
        "domain_quality":q,
        "max_difficulty_solved":solved,
        "robustness":robust,
        "adaptation":adaptation,
        "transfer":transfer,
        "preservation":preservation,
        "efficiency":efficiency,
        "efficiency_observation_status":eff_status,
        "critical_failures":_critical_failures(verified,float(policy["solved_threshold"])),
        "longitudinal_evidence":{"verified_generations":len(generations),"generation_ids":sorted(generations)},
        "causal_confidence":causal_conf,
    }
    maturity=derive_maturity(vector,policy)
    mode,needed=_mode(payload,maturity,vector)
    return {
        "schema":"PROFILE_ASSESSMENT_V2",
        "assessment_status":"EVIDENCE_SUFFICIENT" if mode is not None else "NEEDS_MORE_EVIDENCE",
        "maturity":maturity,
        "competency_vector":vector,
        "evolution_mode":mode,
        "evidence_needed":needed,
        "structural_compatibility":payload.get("structural_status","UNKNOWN"),
        "architecture_fit":payload.get("architecture_status","UNKNOWN"),
        "next_action":"TARGETED_EVIDENCE_ACQUISITION" if needed else "CONTINUE_EVOLUTION_FLOW",
        "write_authorized":False,
        "admission_required":True,
        "maturity_is_derived":True,
    }

# Compatibility alias is deliberately explicit; V1 remains separately available.
assess_profile=assess_profile_v2
