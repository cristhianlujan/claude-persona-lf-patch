#!/usr/bin/env python3
import argparse, copy, json, os, subprocess
from pathlib import Path
from typing import Any, Dict, Optional

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
        p={"status":"PASS","evidence":f"selftest:{k}"}
        req=(c["cheap_preflight"].get("check_requirements") or {}).get(k) or {}
        if req.get("required_subproofs"): p["resolved"]=list(req["required_subproofs"])
        if req.get("bindings_required"): p["bindings"]=[{"object_identity":"public.example","resolved_fields":["id"],"evidence_ref":"selftest:schema"}]
        checks[k]=p
    closure={k:{"status":"PASS","evidence":f"selftest:{k}"} for k in c["hard_guard_promotion"]["required_closure"]}
    causal={"ekb_code":"GOV-010","target_asset":"S30","primary_gate":"SELFTEST_GATE","role":"WRITER","owner":"S30",
            "observed_active_writers":[{"ekb_code":"GOV-010","target_asset":"S30","primary_gate":"SELFTEST_GATE","owner":"S30","state":"ACTIVE","source_ref":"selftest:owner"}],
            "transfer":{"is_transfer":False},"evidence":"selftest:causal-lane"}
    return {"receipt_version":"v0.4","receipt_mode":mode,"lane":"S30-A","owner":"S30","base_main_sha":"a"*40,
            "intended_material_action":("SELF_GOVERNANCE_GATE_REPAIR" if mode=="REPAIR_PREWRITE" else "SELFTEST"),"sequence_resolution":seq,"preflight_checks":checks,
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
            "owner_authorized_merge":mode=="CLOSEOUT",
            "owner_authorized_repair":mode=="REPAIR_PREWRITE",
            "repair_reason":"selftest repair" if mode=="REPAIR_PREWRITE" else None,
            "repair_target_ekb_codes":["DB-001","GOV-010"] if mode=="REPAIR_PREWRITE" else [],
            "evidence":{"mode":"SELFTEST"}}

def self_test(c):
    e="a"*40; p=positive_fixture(c); results={}
    pos=evaluate(c,p,e); assert pos["result"]=="PASS_TO_MATERIAL_WORK"; results["positive_prewrite"]=pos["result"]
    x=copy.deepcopy(p); x["preflight_checks"].pop("IMPORT_CLOSURE"); r=evaluate(c,x,e); assert r["result"].startswith("FAIL_"); results["negative_missing_preflight"]=r["result"]
    x=copy.deepcopy(p); x["preflight_checks"]["SCHEMA_AND_CONSTRAINTS_RESOLVED"]["resolved"].remove("DEPENDENT_SQL_FUNCTION_SIGNATURES"); r=evaluate(c,x,e); assert "SCHEMA_AND_CONSTRAINTS_RESOLVED:DEPENDENT_SQL_FUNCTION_SIGNATURES" in r["failed_checks"]; results["negative_unresolved_sql_function_signature"]=r["result"]
    x=copy.deepcopy(p); x["hard_guard_candidates"][0]["closure"]={"EKB_UPDATED":{"status":"PASS","evidence":"text only"}}; r=evaluate(c,x,e); assert any("DB-001:DETECTOR_IMPLEMENTED" in z for z in r["hard_guard_failures"]); results["negative_text_only_ekb"]=r["result"]
    x=copy.deepcopy(p); r=evaluate(c,x,"b"*40); assert "BASE_MAIN_SHA_MISMATCH" in r["failed_checks"]; results["negative_stale_base"]=r["result"]
    x=copy.deepcopy(p); x["frontier"]["blockers"]=["UNSCOPED"]; r=evaluate(c,x,e); assert "BLOCKER_NOT_OBJECT:0" in r["blocker_failures"]; results["negative_unscoped_blocker"]=r["result"]
    x=copy.deepcopy(p); x["sequence_resolution"]["DATA_ACCESS_BINDINGS"]={"status":"NOT_REQUIRED_WITH_REASON","evidence":"bypass"}; r=evaluate(c,x,e); assert "DATA_ACCESS_BINDINGS" in r["sequence_failures"]; results["negative_not_required_data_access"]=r["result"]
    x=copy.deepcopy(p); x["preflight_checks"]["REQUIRED_FILES_EXIST"].pop("evidence"); r=evaluate(c,x,e); assert "REQUIRED_FILES_EXIST:EVIDENCE_MISSING" in r["failed_checks"]; results["negative_missing_evidence"]=r["result"]
    x=copy.deepcopy(p); x["hard_guard_candidates"]=[z for z in x["hard_guard_candidates"] if z["ekb_code"]!="GOV-010"]; r=evaluate(c,x,e); assert "GOV-010:CANDIDATE_MISSING" in r["hard_guard_failures"]; results["negative_missing_applicable_hard_guard"]=r["result"]
    cclose=positive_fixture(c,"CLOSEOUT"); r=evaluate(c,cclose,e); assert r["result"]==c["claim_ceiling"]; results["positive_closeout_owner_merge"]=r["result"]
    x=copy.deepcopy(cclose); x["owner_authorized_merge"]=False; r=evaluate(c,x,e); assert "SAFETY_READBACK:CLOSEOUT_MERGE_NOT_OWNER_AUTHORIZED" in r["failed_checks"]; results["negative_closeout_unauthorized_merge"]=r["result"]
    repair=positive_fixture(c,"REPAIR_PREWRITE")
    for cand in repair["hard_guard_candidates"]:
        cand["closure"]={"EKB_UPDATED":{"status":"PASS","evidence":"selftest:EKB_UPDATED"}}
    r=evaluate(c,repair,e); assert r["result"]=="PASS_TO_BOUNDED_GUARD_REPAIR" and r["bounded_repair_allowed"] is True; results["positive_bounded_guard_repair"]=r["result"]
    x=copy.deepcopy(repair); x["owner_authorized_repair"]=False; r=evaluate(c,x,e); assert "REPAIR_MODE:OWNER_AUTHORIZATION_MISSING" in r["failed_checks"]; results["negative_repair_without_owner_auth"]=r["result"]
    # S30-R10 causal-lane regressions.
    writer=positive_fixture(c); r=evaluate(c,writer,e); assert r["result"]=="PASS_TO_MATERIAL_WORK"; results["positive_single_writer_acquire"]=r["result"]
    x=copy.deepcopy(writer); x["causal_lane_ownership"]["observed_active_writers"].append({"ekb_code":"GOV-010","target_asset":"S30","primary_gate":"SELFTEST_GATE","owner":"OTHER_WRITER","state":"IN_PROGRESS","source_ref":"selftest:collision"}); r=evaluate(c,x,e); assert any("BLOCK_CAUSAL_LANE_ALREADY_OWNED" in z for z in r["blocker_failures"]); results["negative_second_writer_same_key"]=r["result"]
    audit=positive_fixture(c); audit["owner"]="S30-QUALITY-AUDITOR"; audit["causal_lane_ownership"]["role"]="READ_ONLY_AUDIT"; audit["causal_lane_ownership"]["owner"]="S30-QUALITY-AUDITOR"; r=evaluate(c,audit,e); assert r["result"]=="PASS_TO_READ_ONLY_PARALLEL" and r["material_work_allowed"] is False; results["positive_parallel_read_only"]=r["result"]
    x=copy.deepcopy(writer); x["causal_lane_ownership"]["transfer"]={"is_transfer":True,"upstream_owner_state":"OPEN","fresh_currentness":False,"stale_receipts_invalidated":False,"evidence_revalidated":False}; r=evaluate(c,x,e); assert any("TRANSFER_FRESH_CURRENTNESS_MISSING" in z for z in r["blocker_failures"]); results["negative_stale_transfer"]=r["result"]
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
    touched=sorted(set(c["ci_enforcement"]["fresh_receipt_trigger_paths"]).intersection(changed))
    if not touched: return {"status":"PASS","fresh_receipt_evaluated":False,"reason":"NO_S30_GATE_TRIGGER_PATH_CHANGED","changed_file_count":len(changed)}
    if expected is None: raise AssertionError("S30 gate paths changed but expected base unresolved")
    receipt=load_json(receipt_path)
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
