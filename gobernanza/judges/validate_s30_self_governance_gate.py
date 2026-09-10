#!/usr/bin/env python3
import argparse, copy, hashlib, json, os, subprocess
from pathlib import Path
from typing import Any, Dict, Mapping, Optional

CONTRACT_DEFAULT = Path(__file__).resolve().parents[1] / "contratos" / "s30_self_governance_gate_v1.json"
DEFAULT_RECEIPT = Path("sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json")

def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))

def nonempty(v: Any) -> bool:
    if isinstance(v, str): return bool(v.strip())
    if isinstance(v, (list, dict)): return bool(v)
    return v is not None

def proof_pass(c: Dict[str, Any], v: Any) -> bool:
    return isinstance(v, dict) and str(v.get("status","")).upper() in set(c["proof_policy"]["pass_statuses"])

def proof_evidence(v: Any) -> bool:
    return isinstance(v, dict) and nonempty(v.get("evidence"))

def canonical_sha256(v: Any) -> str:
    raw=json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()

def gate_evidence_failures(c: Dict[str, Any], r: Dict[str, Any]):
    cfg=c.get("gate_evidence_envelope") or {}
    prefix=cfg.get("missing_action","BLOCK_GATE_ENVELOPE_INCOMPLETE")
    mismatch=cfg.get("hash_mismatch_action","BLOCK_GATE_ENVELOPE_HASH_MISMATCH")
    env=r.get("gate_evidence_envelope")
    failures=[]
    if not isinstance(env,dict): return [f"{prefix}:MISSING_OR_NOT_OBJECT"]
    for f in cfg.get("required_fields") or []:
        if f not in env: failures.append(f"{prefix}:FIELD_MISSING:{f}")
    for f in cfg.get("non_null_fields") or []:
        if f in env and not nonempty(env.get(f)): failures.append(f"{prefix}:FIELD_NULL_OR_EMPTY:{f}")
    if "input_exact" in env and nonempty(env.get("input_sha256")):
        if env.get("input_sha256") != canonical_sha256(env.get("input_exact")):
            failures.append(f"{mismatch}:input_sha256")
    if "output_exact" in env and nonempty(env.get("output_sha256")):
        if env.get("output_sha256") != canonical_sha256(env.get("output_exact")):
            failures.append(f"{mismatch}:output_sha256")
    if env.get("execution_mode") not in set(cfg.get("allowed_execution_modes") or []):
        failures.append(f"{prefix}:EXECUTION_MODE_INVALID")
    if env.get("environment") not in set(cfg.get("allowed_environments") or []):
        failures.append(f"{prefix}:ENVIRONMENT_INVALID")
    if env.get("promotion_authority") not in set(cfg.get("allowed_promotion_authorities") or []):
        failures.append(f"{prefix}:PROMOTION_AUTHORITY_INVALID")
    for dim,allowed in (cfg.get("required_dimension_statuses") or {}).items():
        proof=env.get(dim)
        if not isinstance(proof,dict):
            failures.append(f"{prefix}:DIMENSION_INVALID:{dim}"); continue
        if str(proof.get("status","")).upper() not in set(allowed or []):
            failures.append(f"{prefix}:DIMENSION_STATUS_INVALID:{dim}")
        if not nonempty(proof.get("evidence")):
            failures.append(f"{prefix}:DIMENSION_EVIDENCE_MISSING:{dim}")
    if not isinstance(env.get("ekb_action"),dict) or not env.get("ekb_action"):
        failures.append(f"{prefix}:EKB_ACTION_INVALID")
    if not isinstance(env.get("repair_allowed"),bool):
        failures.append(f"{prefix}:REPAIR_ALLOWED_NOT_BOOL")
    if r.get("receipt_mode")=="REPAIR_PREWRITE" and env.get("repair_allowed") is not True:
        failures.append(f"{prefix}:REPAIR_NOT_ALLOWED")
    return failures

def git_write_binding_failures(c: Dict[str, Any], r: Dict[str, Any]):
    cfg=c.get("git_write_broker") or {}; bc=cfg.get("binding_contract") or {}
    prefix=cfg.get("binding_missing_action","BLOCK_GIT_WRITE_BINDING_INVALID")
    b=r.get("git_write_binding"); failures=[]
    if not isinstance(b,dict): return [f"{prefix}:MISSING_OR_NOT_OBJECT"]
    for f in bc.get("required_fields") or []:
        if f not in b or not nonempty(b.get(f)):
            failures.append(f"{prefix}:FIELD_MISSING_OR_EMPTY:{f}")
    exact={
        "request_schema":cfg.get("request_schema"),
        "ruleset_id":cfg.get("ruleset_id"),
        "ruleset_name":cfg.get("ruleset_name"),
        "ruleset_enforcement":cfg.get("enforcement"),
        "ruleset_ref_pattern":cfg.get("ref_pattern"),
        "bypass_actor_type":(cfg.get("bypass_actor") or {}).get("actor_type"),
        "deploy_key_id":(cfg.get("bypass_actor") or {}).get("deploy_key_id"),
        "deploy_key_title":(cfg.get("bypass_actor") or {}).get("deploy_key_title"),
        "workflow_path":cfg.get("broker_workflow"),
        "secret_name":cfg.get("broker_secret_name"),
    }
    for k,v in exact.items():
        if b.get(k)!=v: failures.append(f"{prefix}:MISMATCH:{k}")
    if b.get("direct_user_can_bypass") is not False:
        failures.append(f"{prefix}:DIRECT_USER_BYPASS_NOT_FALSE")
    neg=b.get("direct_connector_negative")
    required_neg=bc.get("direct_connector_negative_required") or {}
    if not isinstance(neg,dict): failures.append(f"{prefix}:DIRECT_CONNECTOR_NEGATIVE_INVALID")
    else:
        for k,v in required_neg.items():
            if neg.get(k) is not v: failures.append(f"{prefix}:DIRECT_CONNECTOR_NEGATIVE:{k}")
    probe=b.get("broker_probe")
    if not isinstance(probe,dict) or probe.get("status")!=bc.get("broker_probe_status_required"):
        failures.append(f"{prefix}:BROKER_PROBE_INVALID")
    elif not isinstance(probe.get("commit_sha"),str) or len(probe.get("commit_sha"))!=40:
        failures.append(f"{prefix}:BROKER_PROBE_SHA_INVALID")
    if b.get("workflow_dispatch_wired") is not True:
        failures.append(f"{prefix}:WORKFLOW_DISPATCH_NOT_WIRED")
    if b.get("secret_required_before_dispatch") is not True:
        failures.append(f"{prefix}:SECRET_NOT_REQUIRED_BEFORE_DISPATCH")
    if not isinstance(b.get("secret_present"),bool):
        failures.append(f"{prefix}:SECRET_PRESENT_NOT_BOOL")
    staging=cfg.get("staging_prefix",""); protected=cfg.get("protected_branch_prefix","")
    if not isinstance(b.get("source_branch"),str) or not b.get("source_branch","").startswith(staging):
        failures.append(f"{prefix}:SOURCE_NOT_STAGING")
    if not isinstance(b.get("target_branch"),str) or not b.get("target_branch","").startswith(protected):
        failures.append(f"{prefix}:TARGET_NOT_PROTECTED_S30")
    if b.get("source_branch")==b.get("target_branch"):
        failures.append(f"{prefix}:SOURCE_EQUALS_TARGET")
    if b.get("base_main_sha")!=r.get("base_main_sha"):
        failures.append(f"{prefix}:BASE_MAIN_SHA_MISMATCH")
    status=b.get("status")
    if status not in set(bc.get("allowed_statuses") or []):
        failures.append(f"{prefix}:STATUS_INVALID")
    elif status=="STAGED_VALIDATION":
        sc=bc.get("staged_validation") or {}
        if b.get("promotion_authority")!=sc.get("promotion_authority"):
            failures.append(f"{prefix}:STAGED_PROMOTION_AUTHORITY_INVALID")
        if b.get("secret_present") not in sc.get("secret_present_allowed",[]):
            failures.append(f"{prefix}:STAGED_SECRET_STATE_INVALID")
    elif status=="OPERATIONAL":
        oc=bc.get("operational") or {}
        if oc.get("secret_present_required") and b.get("secret_present") is not True:
            failures.append(f"{prefix}:OPERATIONAL_SECRET_MISSING")
        if b.get("promotion_authority")!=oc.get("promotion_authority"):
            failures.append(f"{prefix}:OPERATIONAL_PROMOTION_AUTHORITY_INVALID")
    for ref_field in ("ruleset_readback_ref","supabase_readback_ref"):
        if not nonempty(b.get(ref_field)): failures.append(f"{prefix}:{ref_field.upper()}_MISSING")
    return failures

def broker_scope_decision(c: Dict[str, Any], changed_paths, receipt_path: str, receipt: Optional[Mapping[str, Any]] = None, path_modes: Optional[Mapping[str, str]] = None) -> Dict[str, Any]:
    cfg=c.get("git_write_broker") or {}
    scope_fail=cfg.get("scope_failure_action","BLOCK_S30_BROKER_PATH_OUTSIDE_ALLOWLIST")
    receipt_fail=cfg.get("candidate_receipt_failure_action","BLOCK_S30_BROKER_CANDIDATE_RECEIPT_INVALID")
    changed=sorted(set(str(x).strip() for x in (changed_paths or []) if str(x).strip()))
    if not changed:
        return {"status":"BLOCKED","mode":None,"blocking_code":"BLOCK_S30_BROKER_EMPTY_CHANGESET","changed_paths":[]}
    for path in changed:
        parts=path.split("/")
        if path.startswith("/") or any(part in {"", ".", ".."} for part in parts):
            return {"status":"BLOCKED","mode":None,"blocking_code":scope_fail,"changed_paths":changed,"detail":"PATH_NOT_CANONICAL"}
    if cfg.get("require_regular_files") is True:
        if not isinstance(path_modes,Mapping):
            return {"status":"BLOCKED","mode":None,"blocking_code":"BLOCK_S30_BROKER_GIT_MODE_UNRESOLVED","changed_paths":changed}
        allowed_modes=set(cfg.get("allowed_git_modes") or [])
        bad_modes=sorted(path for path in changed if path_modes.get(path) not in allowed_modes)
        if bad_modes:
            return {"status":"BLOCKED","mode":None,"blocking_code":"BLOCK_S30_BROKER_NONREGULAR_PATH","changed_paths":changed,"detail":",".join(bad_modes)}

    repair=set(cfg.get("repair_allowed_paths") or [])
    repair_cfg=(cfg.get("scope_modes") or {}).get("REPAIR") or {}
    canonical_repair_receipt=repair_cfg.get("receipt_path","sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json")
    if set(changed).issubset(repair) and receipt_path==canonical_repair_receipt:
        return {"status":"PASS","mode":"REPAIR","blocking_code":None,"changed_paths":changed}

    prefixes=tuple(cfg.get("candidate_allowed_prefixes") or [])
    denied=tuple(cfg.get("candidate_denied_prefixes") or [])
    if not prefixes:
        return {"status":"BLOCKED","mode":None,"blocking_code":scope_fail,"changed_paths":changed,"detail":"CANDIDATE_PREFIX_POLICY_MISSING"}
    if len(changed)>int(cfg.get("candidate_max_changed_files",0) or 0):
        return {"status":"BLOCKED","mode":None,"blocking_code":scope_fail,"changed_paths":changed,"detail":"CANDIDATE_CHANGESET_TOO_LARGE"}
    if any(not path.startswith(prefixes) for path in changed):
        return {"status":"BLOCKED","mode":None,"blocking_code":scope_fail,"changed_paths":changed,"detail":"PATH_OUTSIDE_CANDIDATE_PREFIX"}
    if denied and any(path.startswith(denied) for path in changed):
        return {"status":"BLOCKED","mode":None,"blocking_code":scope_fail,"changed_paths":changed,"detail":"CANDIDATE_CONTROL_PATH_DENIED"}

    requirements=cfg.get("candidate_receipt_requirements") or {}
    if requirements.get("receipt_must_be_changed") and receipt_path not in changed:
        return {"status":"BLOCKED","mode":None,"blocking_code":receipt_fail,"changed_paths":changed,"detail":"RECEIPT_NOT_IN_CHANGESET"}
    if requirements.get("receipt_must_be_under_candidate_prefix") and not receipt_path.startswith(prefixes):
        return {"status":"BLOCKED","mode":None,"blocking_code":receipt_fail,"changed_paths":changed,"detail":"RECEIPT_OUTSIDE_CANDIDATE_PREFIX"}
    if requirements.get("receipt_must_not_be_under_denied_prefix") and denied and receipt_path.startswith(denied):
        return {"status":"BLOCKED","mode":None,"blocking_code":receipt_fail,"changed_paths":changed,"detail":"RECEIPT_IN_CONTROL_PREFIX"}
    if cfg.get("require_regular_files") is True and path_modes.get(receipt_path) != cfg.get("candidate_receipt_git_mode"):
        return {"status":"BLOCKED","mode":None,"blocking_code":receipt_fail,"changed_paths":changed,"detail":"RECEIPT_GIT_MODE_INVALID"}
    required_mode=requirements.get("receipt_mode_required")
    if receipt is not None and required_mode and receipt.get("receipt_mode")!=required_mode:
        return {"status":"BLOCKED","mode":None,"blocking_code":receipt_fail,"changed_paths":changed,"detail":"RECEIPT_MODE_INVALID"}
    return {"status":"PASS","mode":"CANDIDATE","blocking_code":None,"changed_paths":changed}


def blocked(preflight, seq, checks, hard, blockers):
    if seq: first=f"SEQUENCE:{seq[0]}"
    elif checks: first=f"PREFLIGHT:{checks[0]}"
    elif hard: first=f"HARD_GUARD:{hard[0]}"
    elif blockers and str(blockers[0]).startswith("CAUSAL_LANE:"): first=str(blockers[0])
    else: first=f"BLOCKER_CONTRACT:{blockers[0]}"
    return {"result":preflight["failure_action"],"first_bad_hop":first,"material_work_allowed":False,
            "bounded_repair_allowed":False,"sequence_failures":seq,"failed_checks":checks,"hard_guard_failures":hard,
            "blocker_failures":blockers,"claim_ceiling":"SELF_GOVERNANCE_PREEXECUTION_ASSURANCE_BLOCKED"}

def causal_lane_failures(c: Dict[str, Any], r: Dict[str, Any]):
    cfg=c.get("causal_lane_ownership") or {}; lane=r.get("causal_lane_ownership")
    failures=[]
    if not isinstance(lane,dict):
        return ["CAUSAL_LANE:MISSING_OR_NOT_OBJECT"],None
    for f in cfg.get("key_fields") or []:
        if not nonempty(lane.get(f)): failures.append(f"CAUSAL_LANE:KEY_FIELD_MISSING:{f}")
    role=lane.get("role")
    valid_roles={cfg.get("writer_role")} | set(cfg.get("read_only_roles") or [])
    if role not in valid_roles: failures.append("CAUSAL_LANE:ROLE_INVALID")
    if not nonempty(lane.get("owner")): failures.append("CAUSAL_LANE:OWNER_MISSING")
    observed=lane.get("observed_active_writers")
    if not isinstance(observed,list):
        failures.append("CAUSAL_LANE:OBSERVED_ACTIVE_WRITERS_NOT_LIST"); observed=[]
    key=tuple(lane.get(f) for f in cfg.get("key_fields") or [])
    active_states=set(cfg.get("active_writer_states") or [])
    same_key=[]
    for i,item in enumerate(observed):
        if not isinstance(item,dict):
            failures.append(f"CAUSAL_LANE:ACTIVE_WRITER_NOT_OBJECT:{i}"); continue
        if not nonempty(item.get("source_ref")): failures.append(f"CAUSAL_LANE:ACTIVE_WRITER_SOURCE_REF_MISSING:{i}")
        item_key=tuple(item.get(f) for f in cfg.get("key_fields") or [])
        if item_key==key and item.get("state") in active_states: same_key.append(item)
    if role==cfg.get("writer_role"):
        if cfg.get("writer_must_match_receipt_owner") and lane.get("owner")!=r.get("owner"):
            failures.append("CAUSAL_LANE:WRITER_OWNER_RECEIPT_OWNER_MISMATCH")
        if len(same_key)==0:
            failures.append("CAUSAL_LANE:WRITER_OWNERSHIP_NOT_ACQUIRED")
        elif len(same_key)>1 or same_key[0].get("owner")!=lane.get("owner"):
            failures.append(f"CAUSAL_LANE:{cfg.get('blocking_code','BLOCK_CAUSAL_LANE_ALREADY_OWNED')}")
    elif role in set(cfg.get("read_only_roles") or []):
        if r.get("receipt_mode")=="REPAIR_PREWRITE": failures.append("CAUSAL_LANE:READ_ONLY_ROLE_CANNOT_REPAIR")
    transfer=lane.get("transfer") or {"is_transfer":False}
    if not isinstance(transfer,dict):
        failures.append("CAUSAL_LANE:TRANSFER_NOT_OBJECT")
    elif transfer.get("is_transfer") is True:
        if transfer.get("upstream_owner_state") not in ("CLOSED","SUPERSEDED"):
            failures.append("CAUSAL_LANE:TRANSFER_UPSTREAM_NOT_CLOSED_OR_SUPERSEDED")
        if transfer.get("fresh_currentness") is not True:
            failures.append("CAUSAL_LANE:TRANSFER_FRESH_CURRENTNESS_MISSING")
        if transfer.get("stale_receipts_invalidated") is not True:
            failures.append("CAUSAL_LANE:TRANSFER_STALE_RECEIPTS_NOT_INVALIDATED")
        if transfer.get("evidence_revalidated") is not True:
            failures.append("CAUSAL_LANE:TRANSFER_EVIDENCE_NOT_REVALIDATED")
    return failures,role

def evaluate(c: Dict[str, Any], r: Dict[str, Any], expected_base: Optional[str]=None) -> Dict[str, Any]:
    seqf=[]; checks=[]; hard=[]; blockf=[]
    mode=r.get("receipt_mode")
    if not expected_base: checks.append("EXPECTED_BASE_MAIN_SHA_ARGUMENT_MISSING")
    elif r.get("base_main_sha") != expected_base: checks.append("BASE_MAIN_SHA_MISMATCH")
    for f in c["consumer_interface"]["input_required"]:
        if f not in r: checks.append(f"INPUT_FIELD_MISSING:{f}")
    checks.extend(gate_evidence_failures(c,r))
    checks.extend(git_write_binding_failures(c,r))

    seq=r.get("sequence_resolution") or {}
    for step in c["mandatory_sequence"][:-1]:
        p=seq.get(step)
        if not proof_pass(c,p): seqf.append(step)
        elif c["proof_policy"]["evidence_required_for_every_pass"] and not proof_evidence(p):
            seqf.append(f"{step}:EVIDENCE_MISSING")

    ekb=seq.get("EKB_APPLICABLE") or {}
    loaded=ekb.get("loaded_codes") if isinstance(ekb,dict) else None
    if not isinstance(loaded,list) or not loaded: checks.append("EKB_APPLICABLE:LOADED_CODES_MISSING")

    da=seq.get("DATA_ACCESS_BINDINGS") or {}
    da_mode=da.get("mode") if isinstance(da,dict) else None
    if da_mode not in c["proof_policy"]["data_access_modes"]:
        checks.append("DATA_ACCESS_BINDINGS:MODE_UNRESOLVED")
    schema=seq.get("SCHEMA_CONTRACT") or {}
    if da_mode=="SCHEMA_CONTRACT_FALLBACK":
        bindings=schema.get("schema_bindings") if isinstance(schema,dict) else None
        if not isinstance(bindings,list) or not bindings: checks.append("SCHEMA_CONTRACT:FALLBACK_BINDINGS_MISSING")

    pf=c["cheap_preflight"]; obs=r.get("preflight_checks") or {}
    for name in pf["checks"]:
        p=obs.get(name)
        if not proof_pass(c,p): checks.append(name); continue
        if c["proof_policy"]["evidence_required_for_every_pass"] and not proof_evidence(p):
            checks.append(f"{name}:EVIDENCE_MISSING"); continue
        req=(pf.get("check_requirements") or {}).get(name) or {}
        rs=set(p.get("resolved") or []) if isinstance(p,dict) else set()
        for sub in req.get("required_subproofs") or []:
            if sub not in rs: checks.append(f"{name}:{sub}")
        if req.get("bindings_required") and not (isinstance(p.get("bindings"),list) and p["bindings"]):
            checks.append(f"{name}:BINDINGS_MISSING")

    frontier=r.get("frontier")
    if not isinstance(frontier,dict): blockf.append("FRONTIER_MISSING_OR_NOT_OBJECT")
    else:
        for f in c["frontier_contract"]["required_fields"]:
            if f not in frontier: blockf.append(f"FRONTIER_FIELD_MISSING:{f}")
        blockers=frontier.get("blockers")
        if not isinstance(blockers,list): blockf.append("FRONTIER_BLOCKERS_NOT_LIST"); blockers=[]
        for i,b in enumerate(blockers):
            if not isinstance(b,dict): blockf.append(f"BLOCKER_NOT_OBJECT:{i}"); continue
            for f in c["blocker_contract"]["required_fields"]:
                if f not in b or not nonempty(b.get(f)): blockf.append(f"BLOCKER_FIELD_MISSING_OR_EMPTY:{i}:{f}")
            if "independent_safe_work" in b and not isinstance(b["independent_safe_work"],list):
                blockf.append(f"BLOCKER_SAFE_WORK_NOT_LIST:{i}")
        if not isinstance(frontier.get("safe_parallel_work"),list): blockf.append("FRONTIER_SAFE_PARALLEL_NOT_LIST")

    causal_failures,causal_role=causal_lane_failures(c,r); blockf.extend(causal_failures)

    applicable=r.get("applicable_ekb") or []
    if not isinstance(applicable,list): checks.append("APPLICABLE_EKB_NOT_LIST"); applicable=[]
    applicable_codes=[]; triggered=set(); trigger_any=set(c["hard_guard_promotion"]["trigger_any"])
    for i,item in enumerate(applicable):
        if not isinstance(item,dict) or not nonempty(item.get("code")):
            checks.append(f"APPLICABLE_EKB_INVALID:{i}"); continue
        code=item["code"]; applicable_codes.append(code)
        if set(item.get("triggers") or []).intersection(trigger_any): triggered.add(code)
    if isinstance(loaded,list):
        for code in sorted(set(applicable_codes)-set(loaded)): checks.append(f"EKB_NOT_LOADED:{code}")

    candidates=r.get("hard_guard_candidates") or []
    if not isinstance(candidates,list): hard.append("HARD_GUARD_CANDIDATES_NOT_LIST"); candidates=[]
    by_code={x.get("ekb_code"):x for x in candidates if isinstance(x,dict) and nonempty(x.get("ekb_code"))}
    repair_targets=set(r.get("repair_target_ekb_codes") or []) if mode=="REPAIR_PREWRITE" else set()
    for code in sorted(triggered):
        cand=by_code.get(code)
        if cand is None: hard.append(f"{code}:CANDIDATE_MISSING"); continue
        closure=cand.get("closure") or {}
        required_closure = (
            c["repair_mode"]["hard_guard_closure_required_before_repair"]
            if mode=="REPAIR_PREWRITE" and code in repair_targets
            else c["hard_guard_promotion"]["required_closure"]
        )
        for req in required_closure:
            p=closure.get(req)
            if not proof_pass(c,p): hard.append(f"{code}:{req}")
            elif c["proof_policy"]["evidence_required_for_every_pass"] and not proof_evidence(p):
                hard.append(f"{code}:{req}:EVIDENCE_MISSING")

    safety=r.get("safety_readback") or {}
    for k in ("runtime_changed","production_changed","scheduler_changed","s26_mutated"):
        if safety.get(k) is not False: checks.append(f"SAFETY_READBACK:{k}")
    if mode=="PREWRITE":
        if safety.get("main_merged") is not False: checks.append("SAFETY_READBACK:PREWRITE_MAIN_ALREADY_MERGED")
    elif mode=="REPAIR_PREWRITE":
        if safety.get("main_merged") is not False: checks.append("SAFETY_READBACK:REPAIR_PREWRITE_MAIN_ALREADY_MERGED")
        if r.get("owner_authorized_repair") is not True: checks.append("REPAIR_MODE:OWNER_AUTHORIZATION_MISSING")
        if r.get("intended_material_action") != c["repair_mode"]["required_intended_material_action"]:
            checks.append("REPAIR_MODE:INTENDED_ACTION_INVALID")
        if not nonempty(r.get("repair_reason")): checks.append("REPAIR_MODE:REASON_MISSING")
        if not isinstance(r.get("repair_target_ekb_codes"),list) or not r.get("repair_target_ekb_codes"):
            checks.append("REPAIR_MODE:TARGET_EKB_CODES_MISSING")
        elif not set(triggered).issubset(set(r["repair_target_ekb_codes"])):
            checks.append("REPAIR_MODE:TRIGGERED_EKB_NOT_ALL_TARGETED")
    elif mode=="CLOSEOUT":
        if safety.get("main_merged") is True and r.get("owner_authorized_merge") is not True:
            checks.append("SAFETY_READBACK:CLOSEOUT_MERGE_NOT_OWNER_AUTHORIZED")
        elif safety.get("main_merged") not in (True,False):
            checks.append("SAFETY_READBACK:CLOSEOUT_MAIN_MERGED_INVALID")
    else: checks.append("RECEIPT_MODE_INVALID")

    if seqf or checks or hard or blockf: return blocked(pf,seqf,checks,hard,blockf)
    if causal_role in set(c["causal_lane_ownership"].get("read_only_roles") or []):
        result="PASS_TO_READ_ONLY_PARALLEL"; material=False; bounded=False
    elif mode=="PREWRITE":
        result="PASS_TO_MATERIAL_WORK"; material=True; bounded=False
    elif mode=="REPAIR_PREWRITE":
        result=c["repair_mode"]["result"]; material=False; bounded=True
    else:
        result=c["claim_ceiling"]; material=False; bounded=False
    return {"result":result,"first_bad_hop":None,"material_work_allowed":material,
            "bounded_repair_allowed":bounded,"sequence_failures":[],"failed_checks":[],
            "hard_guard_failures":[],"blocker_failures":[],"claim_ceiling":c["claim_ceiling"]}

def positive_fixture(c, mode="PREWRITE"):
    seq={k:{"status":"PROVEN","evidence":f"selftest:{k}"} for k in c["mandatory_sequence"][:-1]}
    seq["EKB_APPLICABLE"]["loaded_codes"]=["DB-001","GOV-010"]
    seq["DATA_ACCESS_BINDINGS"]["mode"]="SCHEMA_CONTRACT_FALLBACK"
    seq["SCHEMA_CONTRACT"]["schema_bindings"]=[{"object_identity":"public.example","object_type":"TABLE","resolved_fields":["id"],"evidence_ref":"selftest:schema"}]
    checks={}
    for k in c["cheap_preflight"]["checks"]:
        proof={"status":"PASS","evidence":f"selftest:{k}"}
        req=(c["cheap_preflight"].get("check_requirements") or {}).get(k) or {}
        if req.get("required_subproofs"): proof["resolved"]=list(req["required_subproofs"])
        if req.get("bindings_required"): proof["bindings"]=[{"object_identity":"public.example","resolved_fields":["id"],"evidence_ref":"selftest:schema"}]
        checks[k]=proof
    closure={k:{"status":"PASS","evidence":f"selftest:{k}"} for k in c["hard_guard_promotion"]["required_closure"]}
    causal={"ekb_code":"GOV-010","target_asset":"S30","primary_gate":"SELFTEST_GATE","role":"WRITER","owner":"S30",
            "observed_active_writers":[{"ekb_code":"GOV-010","target_asset":"S30","primary_gate":"SELFTEST_GATE","owner":"S30","state":"ACTIVE","source_ref":"selftest:owner"}],
            "transfer":{"is_transfer":False},"evidence":"selftest:causal-lane"}
    base="a"*40
    broker=c["git_write_broker"]
    binding={
        "status":"STAGED_VALIDATION","request_schema":broker["request_schema"],"ruleset_id":broker["ruleset_id"],
        "ruleset_name":broker["ruleset_name"],"ruleset_enforcement":broker["enforcement"],"ruleset_ref_pattern":broker["ref_pattern"],
        "bypass_actor_type":broker["bypass_actor"]["actor_type"],"deploy_key_id":broker["bypass_actor"]["deploy_key_id"],
        "deploy_key_title":broker["bypass_actor"]["deploy_key_title"],"direct_user_can_bypass":False,
        "direct_connector_negative":{"create_blocked":True,"update_blocked":True},
        "broker_probe":{"status":"PASS","commit_sha":"b"*40,"evidence_ref":"selftest:broker-probe"},
        "workflow_path":broker["broker_workflow"],"workflow_dispatch_wired":True,"secret_name":broker["broker_secret_name"],
        "secret_present":False,"secret_required_before_dispatch":True,"source_branch":broker["staging_prefix"]+"selftest",
        "target_branch":broker["protected_branch_prefix"]+"selftest","base_main_sha":base,"promotion_authority":"NONE",
        "ruleset_readback_ref":"selftest:ruleset","supabase_readback_ref":"selftest:supabase"
    }
    receipt={"receipt_version":"v0.5","receipt_mode":mode,"lane":"S30-A","owner":"S30","base_main_sha":base,
            "intended_material_action":("SELF_GOVERNANCE_GATE_REPAIR" if mode=="REPAIR_PREWRITE" else "SELFTEST"),
            "sequence_resolution":seq,"preflight_checks":checks,
            "frontier":{"current_stage":"S30-A_SELF_GOVERNANCE_PREEXECUTION_ASSURANCE","next_gate":"SELFTEST_NEXT",
                        "blockers":[{"code":"SELFTEST_BLOCKER","affected_scope":"SELFTEST","causal_gate":"SELFTEST_GATE",
                                     "owner":"S30","independent_safe_work":["SELFTEST"],"invalidation_condition":"selftest passes"}],
                        "safe_parallel_work":["SELFTEST"]},
            "causal_lane_ownership":causal,
            "applicable_ekb":[{"code":"DB-001","triggers":["RECURRENT","MACHINE_DETECTABLE"]},
                              {"code":"GOV-010","triggers":["RECURRENT","AVOIDABLE_MATERIAL_WORK"]}],
            "hard_guard_candidates":[{"ekb_code":"DB-001","closure":copy.deepcopy(closure)},
                                     {"ekb_code":"GOV-010","closure":copy.deepcopy(closure)}],
            "safety_readback":{"runtime_changed":False,"production_changed":False,"main_merged":mode=="CLOSEOUT",
                               "scheduler_changed":False,"s26_mutated":False},
            "owner_authorized_merge":mode=="CLOSEOUT","owner_authorized_repair":mode=="REPAIR_PREWRITE",
            "repair_reason":"selftest repair" if mode=="REPAIR_PREWRITE" else None,
            "repair_target_ekb_codes":["DB-001","GOV-010"] if mode=="REPAIR_PREWRITE" else [],
            "evidence":{"mode":"SELFTEST"},"git_write_binding":binding}
    input_exact={"case":"SELFTEST","mode":mode,"base_main_sha":base}
    output_exact={"expected":"PASS","mode":mode}
    receipt["gate_evidence_envelope"]={
        "run_id":"SELFTEST-RUN","gate_id":"SELFTEST-GATE","input_exact":input_exact,"input_sha256":canonical_sha256(input_exact),
        "input_source_ref":"selftest:input","validation_or_transformation_exact":"selftest:evaluate",
        "output_exact":output_exact,"output_sha256":canonical_sha256(output_exact),"output_ref":"selftest:output",
        "execution_mode":"SANDBOX","environment":"NON_PRODUCTION","promotion_authority":"NONE",
        "functional":{"status":"PASS","evidence":"selftest:functional"},"quality":{"status":"PASS","evidence":"selftest:quality"},
        "depth":{"status":"PASS","evidence":"selftest:depth"},"performance":{"status":"PASS_BASELINE","evidence":"selftest:performance"},
        "ekb_action":{"status":"CONSUMED","codes":["DB-001","GOV-010"]},"first_bad_hop":None,"repair_allowed":True
    }
    return receipt

def self_test(c):
    e="a"*40; p=positive_fixture(c); results={}
    pos=evaluate(c,p,e); assert pos["result"]=="PASS_TO_MATERIAL_WORK",pos; results["positive_prewrite"]=pos["result"]
    x=copy.deepcopy(p); x["preflight_checks"].pop("IMPORT_CLOSURE"); r=evaluate(c,x,e); assert r["result"].startswith("FAIL_"); results["negative_missing_preflight"]=r["result"]
    x=copy.deepcopy(p); x["preflight_checks"]["SCHEMA_AND_CONSTRAINTS_RESOLVED"]["resolved"].remove("DEPENDENT_SQL_FUNCTION_SIGNATURES"); r=evaluate(c,x,e); assert "SCHEMA_AND_CONSTRAINTS_RESOLVED:DEPENDENT_SQL_FUNCTION_SIGNATURES" in r["failed_checks"]; results["negative_unresolved_sql_function_signature"]=r["result"]
    x=copy.deepcopy(p); x["hard_guard_candidates"][0]["closure"]={"EKB_UPDATED":{"status":"PASS","evidence":"text only"}}; r=evaluate(c,x,e); assert any("DB-001:DETECTOR_IMPLEMENTED" in z for z in r["hard_guard_failures"]); results["negative_text_only_ekb"]=r["result"]
    x=copy.deepcopy(p); r=evaluate(c,x,"b"*40); assert "BASE_MAIN_SHA_MISMATCH" in r["failed_checks"]; results["negative_stale_base"]=r["result"]
    x=copy.deepcopy(p); x["frontier"]["blockers"]=["UNSCOPED"]; r=evaluate(c,x,e); assert "BLOCKER_NOT_OBJECT:0" in r["blocker_failures"]; results["negative_unscoped_blocker"]=r["result"]
    x=copy.deepcopy(p); x["sequence_resolution"]["DATA_ACCESS_BINDINGS"]={"status":"NOT_REQUIRED_WITH_REASON","evidence":"bypass"}; r=evaluate(c,x,e); assert "DATA_ACCESS_BINDINGS" in r["sequence_failures"]; results["negative_not_required_data_access"]=r["result"]
    x=copy.deepcopy(p); x["preflight_checks"]["REQUIRED_FILES_EXIST"].pop("evidence"); r=evaluate(c,x,e); assert "REQUIRED_FILES_EXIST:EVIDENCE_MISSING" in r["failed_checks"]; results["negative_missing_evidence"]=r["result"]
    x=copy.deepcopy(p); x["hard_guard_candidates"]=[z for z in x["hard_guard_candidates"] if z["ekb_code"]!="GOV-010"]; r=evaluate(c,x,e); assert "GOV-010:CANDIDATE_MISSING" in r["hard_guard_failures"]; results["negative_missing_applicable_hard_guard"]=r["result"]
    cclose=positive_fixture(c,"CLOSEOUT"); r=evaluate(c,cclose,e); assert r["result"]==c["claim_ceiling"],r; results["positive_closeout_owner_merge"]=r["result"]
    x=copy.deepcopy(cclose); x["owner_authorized_merge"]=False; r=evaluate(c,x,e); assert "SAFETY_READBACK:CLOSEOUT_MERGE_NOT_OWNER_AUTHORIZED" in r["failed_checks"]; results["negative_closeout_unauthorized_merge"]=r["result"]
    repair=positive_fixture(c,"REPAIR_PREWRITE")
    for cand in repair["hard_guard_candidates"]: cand["closure"]={"EKB_UPDATED":{"status":"PASS","evidence":"selftest:EKB_UPDATED"}}
    r=evaluate(c,repair,e); assert r["result"]=="PASS_TO_BOUNDED_GUARD_REPAIR" and r["bounded_repair_allowed"] is True,r; results["positive_bounded_guard_repair"]=r["result"]
    x=copy.deepcopy(repair); x["owner_authorized_repair"]=False; r=evaluate(c,x,e); assert "REPAIR_MODE:OWNER_AUTHORIZATION_MISSING" in r["failed_checks"]; results["negative_repair_without_owner_auth"]=r["result"]
    writer=positive_fixture(c); r=evaluate(c,writer,e); assert r["result"]=="PASS_TO_MATERIAL_WORK",r; results["positive_single_writer_acquire"]=r["result"]
    x=copy.deepcopy(writer); x["causal_lane_ownership"]["observed_active_writers"].append({"ekb_code":"GOV-010","target_asset":"S30","primary_gate":"SELFTEST_GATE","owner":"OTHER_WRITER","state":"IN_PROGRESS","source_ref":"selftest:collision"}); r=evaluate(c,x,e); assert any("BLOCK_CAUSAL_LANE_ALREADY_OWNED" in z for z in r["blocker_failures"]); results["negative_second_writer_same_key"]=r["result"]
    audit=positive_fixture(c); audit["owner"]="S30-QUALITY-AUDITOR"; audit["causal_lane_ownership"]["role"]="READ_ONLY_AUDIT"; audit["causal_lane_ownership"]["owner"]="S30-QUALITY-AUDITOR"; r=evaluate(c,audit,e); assert r["result"]=="PASS_TO_READ_ONLY_PARALLEL" and r["material_work_allowed"] is False,r; results["positive_parallel_read_only"]=r["result"]
    x=copy.deepcopy(writer); x["causal_lane_ownership"]["transfer"]={"is_transfer":True,"upstream_owner_state":"OPEN","fresh_currentness":False,"stale_receipts_invalidated":False,"evidence_revalidated":False}; r=evaluate(c,x,e); assert any("TRANSFER_FRESH_CURRENTNESS_MISSING" in z for z in r["blocker_failures"]); results["negative_stale_transfer"]=r["result"]
    x=copy.deepcopy(p); del x["gate_evidence_envelope"]["input_source_ref"]; r=evaluate(c,x,e); assert any("BLOCK_GATE_ENVELOPE_INCOMPLETE:FIELD_MISSING:input_source_ref"==z for z in r["failed_checks"]); results["negative_gate_envelope_missing_field"]=r["result"]
    x=copy.deepcopy(p); x["gate_evidence_envelope"]["input_sha256"]="0"*64; r=evaluate(c,x,e); assert any("BLOCK_GATE_ENVELOPE_HASH_MISMATCH:input_sha256"==z for z in r["failed_checks"]); results["negative_gate_envelope_hash_mismatch"]=r["result"]
    x=copy.deepcopy(p); x["git_write_binding"]["target_branch"]="lf/not-s30-selftest"; r=evaluate(c,x,e); assert any("BLOCK_GIT_WRITE_BINDING_INVALID:TARGET_NOT_PROTECTED_S30"==z for z in r["failed_checks"]); results["negative_broker_target_namespace"]=r["result"]
    x=copy.deepcopy(p); x["git_write_binding"]["status"]="OPERATIONAL"; x["git_write_binding"]["promotion_authority"]="BROKER_ONLY"; x["git_write_binding"]["secret_present"]=False; r=evaluate(c,x,e); assert any("BLOCK_GIT_WRITE_BINDING_INVALID:OPERATIONAL_SECRET_MISSING"==z for z in r["failed_checks"]); results["negative_operational_without_secret"]=r["result"]

    # Physical broker scope regressions: repair is exact, candidate is bounded sandbox-only.
    repair_receipt="sandbox/lf_contract_gate_test/s30_self_governance/s30_a_prewrite_receipt.json"
    repair_paths=["gobernanza/contratos/s30_self_governance_gate_v1.json",repair_receipt]
    repair_modes={path:"100644" for path in repair_paths}
    bs=broker_scope_decision(c,repair_paths,repair_receipt,p,repair_modes); assert bs["status"]=="PASS" and bs["mode"]=="REPAIR",bs; results["positive_broker_repair_scope"]="PASS_REPAIR_SCOPE"
    candidate_receipt="sandbox/lf_contract_gate_test/s30_data_access_candidate/s30_b_prewrite_receipt.json"
    candidate_paths=["sandbox/lf_contract_gate_test/s30_data_access_candidate/lf_data_access_budgeted.py",candidate_receipt]
    candidate=copy.deepcopy(p); candidate["receipt_mode"]="PREWRITE"
    candidate_modes={path:"100644" for path in candidate_paths}
    bs=broker_scope_decision(c,candidate_paths,candidate_receipt,candidate,candidate_modes); assert bs["status"]=="PASS" and bs["mode"]=="CANDIDATE",bs; results["positive_broker_candidate_scope"]="PASS_CANDIDATE_SCOPE"
    bs=broker_scope_decision(c,[candidate_paths[0],".github/workflows/validate-lf-packs.yml"],candidate_receipt,candidate,{candidate_paths[0]:"100644",".github/workflows/validate-lf-packs.yml":"100644"}); assert bs["blocking_code"]==c["git_write_broker"]["scope_failure_action"],bs; results["negative_broker_mixed_control_candidate"]=bs["blocking_code"]
    bs=broker_scope_decision(c,[candidate_paths[0],"sandbox/lf_contract_gate_test/s30_self_governance/rogue.json"],candidate_receipt,candidate,{candidate_paths[0]:"100644","sandbox/lf_contract_gate_test/s30_self_governance/rogue.json":"100644"}); assert bs["blocking_code"]==c["git_write_broker"]["scope_failure_action"],bs; results["negative_broker_candidate_control_prefix"]=bs["blocking_code"]
    bs=broker_scope_decision(c,[candidate_paths[0]],candidate_receipt,candidate,{candidate_paths[0]:"100644"}); assert bs["blocking_code"]==c["git_write_broker"]["candidate_receipt_failure_action"],bs; results["negative_broker_candidate_receipt_missing"]=bs["blocking_code"]
    wrong_mode=copy.deepcopy(candidate); wrong_mode["receipt_mode"]="REPAIR_PREWRITE"; bs=broker_scope_decision(c,candidate_paths,candidate_receipt,wrong_mode,candidate_modes); assert bs["blocking_code"]==c["git_write_broker"]["candidate_receipt_failure_action"],bs; results["negative_broker_candidate_receipt_mode"]=bs["blocking_code"]
    too_many=[f"sandbox/lf_contract_gate_test/s30_data_access_candidate/f{i}.json" for i in range(c["git_write_broker"]["candidate_max_changed_files"]+1)]+[candidate_receipt]
    bs=broker_scope_decision(c,too_many,candidate_receipt,candidate,{path:"100644" for path in too_many}); assert bs["blocking_code"]==c["git_write_broker"]["scope_failure_action"],bs; results["negative_broker_candidate_changeset_too_large"]=bs["blocking_code"]
    bad_modes=dict(candidate_modes); bad_modes[candidate_paths[0]]="120000"
    bs=broker_scope_decision(c,candidate_paths,candidate_receipt,candidate,bad_modes); assert bs["blocking_code"]=="BLOCK_S30_BROKER_NONREGULAR_PATH",bs; results["negative_broker_candidate_symlink"] = bs["blocking_code"]
    assert c["git_write_broker"].get("control_plane_ref_required")=="refs/heads/main"
    assert c["git_write_broker"].get("control_plane_sha_must_equal_base_main") is True
    assert c["git_write_broker"].get("staging_trust")=="UNTRUSTED_INPUT_ONLY"
    results["positive_broker_control_plane_contract"]="PASS_MAIN_PINNED_CONTROL_PLANE"
    return {"status":"PASS","cases":results}

def event_payload():
    p=os.environ.get("GITHUB_EVENT_PATH")
    return json.loads(Path(p).read_text()) if p and Path(p).exists() else {}

def run_git(*args):
    return subprocess.run(["git",*args],check=True,capture_output=True,text=True).stdout.strip()

def fetch_exact(*refs):
    subprocess.run(["git","fetch","origin",*refs,"--depth=1"],check=True)

def ci_changed_and_base():
    event=os.environ.get("GITHUB_EVENT_NAME",""); payload=event_payload()
    if event=="pull_request":
        pr=payload.get("pull_request") or {}
        base_sha=((pr.get("base") or {}).get("sha") or "").strip()
        head_sha=((pr.get("head") or {}).get("sha") or "").strip()
        if len(base_sha)!=40 or len(head_sha)!=40:
            raise AssertionError("pull_request event missing exact base/head SHA")
        fetch_exact(base_sha,head_sha)
        changed=run_git("diff","--name-only",base_sha,head_sha).splitlines()
        return [x.strip() for x in changed if x.strip()], base_sha
    if event=="push" and os.environ.get("GITHUB_REF")=="refs/heads/main":
        before=(payload.get("before") or "").strip(); after=(payload.get("after") or os.environ.get("GITHUB_SHA","")).strip()
        if len(before)!=40 or set(before)<=set("0"): return [],None
        if len(after)!=40: raise AssertionError("push event missing exact after SHA")
        fetch_exact(before,after)
        changed=run_git("diff","--name-only",before,after).splitlines()
        return [x.strip() for x in changed if x.strip()], before
    return [],None

def ci_auto(c, receipt_path):
    changed,expected=ci_changed_and_base()
    ns=(c.get("ci_enforcement") or {}).get("s30_governed_path_namespace") or {}
    governed=sorted(set(ns.get("governed_paths") or []).intersection(changed))
    event=os.environ.get("GITHUB_EVENT_NAME","")
    if event=="pull_request" and governed:
        payload=event_payload(); pr=payload.get("pull_request") or {}; head_ref=((pr.get("head") or {}).get("ref") or "").strip()
        if not head_ref.startswith(ns.get("protected_branch_prefix","") or "__missing_prefix__"):
            raise AssertionError(f"{ns.get('on_mismatch','BLOCK_S30_GOVERNED_PATH_OUTSIDE_PROTECTED_NAMESPACE')}: head={head_ref}")
    touched=sorted(set(c["ci_enforcement"]["fresh_receipt_trigger_paths"]).intersection(changed))
    if not touched: return {"status":"PASS","fresh_receipt_evaluated":False,"reason":"NO_S30_GATE_TRIGGER_PATH_CHANGED","changed_file_count":len(changed)}
    if expected is None: raise AssertionError("S30 gate paths changed but expected base unresolved")
    receipt=load_json(receipt_path)
    if event=="pull_request" and governed and (receipt.get("git_write_binding") or {}).get("status")!="OPERATIONAL":
        raise AssertionError("BLOCK_S30_GOVERNED_PR_WITHOUT_OPERATIONAL_BROKER_BINDING")
    result=evaluate(c,receipt,expected)
    accepted={"PASS_TO_MATERIAL_WORK",c["repair_mode"]["result"]}
    if result["result"] not in accepted: raise AssertionError(json.dumps(result,sort_keys=True))
    if result["result"]==c["repair_mode"]["result"]:
        allowed=set(c["repair_mode"]["allowed_changed_paths"])
        outside=sorted(set(changed)-allowed)
        if outside: raise AssertionError("bounded repair touched disallowed paths: "+",".join(outside))
    return {"status":"PASS","fresh_receipt_evaluated":True,"touched_trigger_paths":touched,
            "changed_file_count":len(changed),"expected_base_main_sha":expected,"result":result["result"]}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--contract",default=str(CONTRACT_DEFAULT)); ap.add_argument("--input")
    ap.add_argument("--expected-base-main-sha"); ap.add_argument("--self-test",action="store_true"); ap.add_argument("--ci-auto",action="store_true")
    ap.add_argument("--ci-receipt",default=str(DEFAULT_RECEIPT)); a=ap.parse_args()
    c=load_json(Path(a.contract)); out={}
    if a.self_test: out["self_test"]=self_test(c)
    if a.input: out["evaluation"]=evaluate(c,load_json(Path(a.input)),a.expected_base_main_sha)
    if a.ci_auto: out["ci_auto"]=ci_auto(c,Path(a.ci_receipt))
    if not out: ap.error("provide --self-test, --input and/or --ci-auto")
    print(json.dumps(out,indent=2,sort_keys=True))
    return 2 if "evaluation" in out and out["evaluation"]["result"]=="FAIL_CLOSED_BEFORE_MATERIAL_WORK" else 0
if __name__=="__main__": raise SystemExit(main())
