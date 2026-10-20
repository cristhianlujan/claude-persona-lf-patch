#!/usr/bin/env python3
"""RW1-01 C3 structured acceptance checker V3.

Adds deterministic structure for security-relevant continuation semantics on top
of the frozen V2 corpus/checker. This is fixture-bound and does not claim Router
runtime, production behavior, or end-to-end execution.
"""
from __future__ import annotations
import argparse, copy, importlib.util, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
V2_PATH = HERE / "validate_rw101_needs_corpus_v2.py"
spec = importlib.util.spec_from_file_location("rw101_v2", V2_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load V2 checker: {V2_PATH}")
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)

PROGRESS_STEPS = {"DERIVE","COMPOSE","TECHNICAL_GOVERNANCE"}
EXTENSION_KEYS = {"per_goal","discovery_receipt_binding"}
PER_GOAL_KEYS = {"goal","mode","permitted_modes","parts","forbidden_subjects","continuation"}
CONTINUATION_KEYS = {"kind","target_goal","selected_subjects","effect_authorized"}
DISCOVERY_BINDING_KEYS = {
    "receipt_ref","scope_request_sha256","scope_case_id","missing_capability","valid",
}
FORBIDDEN_CRITICAL_FREE_TEXT_FIELDS = {
    "safe_continuation","execution_instruction","planned_change_text",
    "free_text_action","free_text_actions",
}

def _arr(v):
    return v if isinstance(v,list) else []

def _unknown_keys(obj, allowed):
    return sorted(set(obj)-set(allowed)) if isinstance(obj,dict) else []

def _base_answer(answer):
    out=copy.deepcopy(answer)
    for key in EXTENSION_KEYS | FORBIDDEN_CRITICAL_FREE_TEXT_FIELDS:
        out.pop(key,None)
    return out

def _seq(answer):
    v=answer.get("next_steps")
    return v if isinstance(v,list) else []

def _resolved_goals(case,answer):
    o=case["oracle"]; seq=_seq(answer)
    if not any(x in PROGRESS_STEPS for x in seq):
        return []
    if o.get("partial_progress_required"):
        return list(_arr(o.get("partial_progress_completed_goals")))
    goals=[x.get("goal") for x in _arr(o.get("responsibility_expectations"))
           if isinstance(x,dict) and x.get("goal")]
    return list(dict.fromkeys(goals))

def _permitted_modes(case):
    modes=[]
    for seq in _arr(case["oracle"].get("acceptable_next_step_sequences")):
        if isinstance(seq,list):
            for step in seq:
                if step in PROGRESS_STEPS and step not in modes:
                    modes.append(step)
    return modes

def check_structured_contract(case,answer):
    errors=[]; cid=case["id"]; o=case["oracle"]
    for key in FORBIDDEN_CRITICAL_FREE_TEXT_FIELDS:
        if key in answer:
            errors.append(f"{cid}:CRITICAL_FREE_TEXT_FIELD_FORBIDDEN:{key}")

    expected_goals=_resolved_goals(case,answer)
    permitted=_permitted_modes(case)
    exclusions=list(_arr(o.get("excluded_subjects")))
    selected_mode=next((x for x in _seq(answer) if x in PROGRESS_STEPS),None)

    per_goal=answer.get("per_goal")
    if not isinstance(per_goal,list):
        errors.append(f"{cid}:PER_GOAL_REQUIRED_ARRAY"); per_goal=[]

    rows=[]
    for row in per_goal:
        if not isinstance(row,dict):
            errors.append(f"{cid}:PER_GOAL_ROW_NOT_OBJECT"); continue
        rows.append(row)
        unknown=_unknown_keys(row,PER_GOAL_KEYS)
        if unknown:
            errors.append(f"{cid}:UNKNOWN_PER_GOAL_FIELDS:{','.join(unknown)}")

    actual_goals=[r.get("goal") for r in rows]
    if actual_goals!=expected_goals:
        errors.append(f"{cid}:PER_GOAL_GOALS_NOT_EXACT")
    if len(actual_goals)!=len(set(actual_goals)):
        errors.append(f"{cid}:PER_GOAL_DUPLICATE_GOAL")

    for row in rows:
        goal=row.get("goal")
        if row.get("permitted_modes")!=permitted:
            errors.append(f"{cid}:PER_GOAL_PERMITTED_MODES_NOT_EXACT:{goal}")
        if row.get("mode") not in permitted or row.get("mode")!=selected_mode:
            errors.append(f"{cid}:PER_GOAL_MODE_NOT_PERMITTED:{goal}")
        if row.get("parts")!=[goal]:
            errors.append(f"{cid}:PER_GOAL_PARTS_NOT_EXACT:{goal}")
        if row.get("forbidden_subjects")!=exclusions:
            errors.append(f"{cid}:PER_GOAL_FORBIDDEN_SUBJECTS_NOT_EXACT:{goal}")

        cont=row.get("continuation")
        if not isinstance(cont,dict):
            errors.append(f"{cid}:STRUCTURED_CONTINUATION_REQUIRED:{goal}"); continue
        unknown=_unknown_keys(cont,CONTINUATION_KEYS)
        if unknown:
            errors.append(f"{cid}:UNKNOWN_CONTINUATION_FIELDS:{','.join(unknown)}")
        if cont.get("kind")!="ROUTE_ONLY":
            errors.append(f"{cid}:CONTINUATION_KIND_NOT_ROUTE_ONLY:{goal}")
        if cont.get("target_goal")!=goal:
            errors.append(f"{cid}:CONTINUATION_GOAL_MISMATCH:{goal}")
        if cont.get("selected_subjects")!=[goal]:
            errors.append(f"{cid}:CONTINUATION_SUBJECTS_NOT_EXACT:{goal}")
        if cont.get("effect_authorized") is not False:
            errors.append(f"{cid}:CONTINUATION_EFFECT_AUTHORITY_FORBIDDEN:{goal}")
        for subject in _arr(cont.get("selected_subjects")):
            if subject in exclusions:
                errors.append(f"{cid}:CONTINUATION_SELECTS_FORBIDDEN_SUBJECT:{subject}")

    has_gap="CAPABILITY_GAP" in _seq(answer)
    binding=answer.get("discovery_receipt_binding")
    if has_gap:
        if not isinstance(binding,dict):
            errors.append(f"{cid}:DISCOVERY_RECEIPT_BINDING_REQUIRED"); binding={}
        else:
            unknown=_unknown_keys(binding,DISCOVERY_BINDING_KEYS)
            if unknown:
                errors.append(f"{cid}:UNKNOWN_DISCOVERY_BINDING_FIELDS:{','.join(unknown)}")
        if binding.get("receipt_ref")!=answer.get("source_search_receipt_ref"):
            errors.append(f"{cid}:DISCOVERY_RECEIPT_REF_MISMATCH")
        if binding.get("scope_request_sha256")!=answer.get("request_sha256"):
            errors.append(f"{cid}:DISCOVERY_RECEIPT_WRONG_SCOPE_HASH")
        if binding.get("scope_case_id")!=cid:
            errors.append(f"{cid}:DISCOVERY_RECEIPT_WRONG_SCOPE_CASE")
        if binding.get("missing_capability")!=answer.get("missing_capability"):
            errors.append(f"{cid}:DISCOVERY_RECEIPT_CAPABILITY_MISMATCH")
        if binding.get("valid") is not True:
            errors.append(f"{cid}:DISCOVERY_RECEIPT_NOT_VALID")
    elif binding is not None:
        errors.append(f"{cid}:DISCOVERY_RECEIPT_BINDING_WITHOUT_GAP")
    return errors

def check_result(case,answer):
    if not isinstance(answer,dict):
        return v2.check_result(case,answer)
    errors=v2.check_result(case,_base_answer(answer))
    errors.extend(check_structured_contract(case,answer))
    return errors

def valid_answer(case,sequence=None):
    ans=v2.valid_answer(case)
    if sequence is not None:
        ans["next_steps"]=list(sequence)
        o=case["oracle"]
        if any(x in PROGRESS_STEPS for x in sequence):
            resolved=(list(_arr(o.get("partial_progress_completed_goals")))
                      if o.get("partial_progress_required")
                      else [x.get("goal") for x in _arr(o.get("responsibility_expectations"))
                            if isinstance(x,dict)])
            ans["candidate_responsibilities"]=[
                {
                    "responsibility_ref":x["responsibility_ref"],
                    "authority_evidence_ref":x["authority_evidence_ref"],
                    "context_evidence_refs":list(x["context_evidence_refs"]),
                    "covered_goals":[x["goal"]],
                    "effect_targets":[],"selected_subjects":[],
                }
                for x in _arr(o.get("responsibility_expectations"))
                if x.get("goal") in set(resolved)
            ]
        else:
            ans.pop("candidate_responsibilities",None)
        if "DISCOVER" in sequence:
            ans["discovery_handoff"]={
                "registered_discovery_capability_ref":"fixture://holdout/discovery",
                "catalog_revision_ref":"fixture://holdout/catalog",
                "unresolved_route_reason":"fixture unresolved capability",
            }
        else:
            ans.pop("discovery_handoff",None)
        if "CAPABILITY_GAP" in sequence:
            ans["source_search_receipt_ref"]="fixture://holdout/search"
            ans["missing_capability"]="fixture-capability"
        else:
            ans.pop("source_search_receipt_ref",None); ans.pop("missing_capability",None)

    goals=_resolved_goals(case,ans); permitted=_permitted_modes(case)
    mode=next((x for x in _seq(ans) if x in PROGRESS_STEPS),None)
    exclusions=list(_arr(case["oracle"].get("excluded_subjects")))
    ans["per_goal"]=[
        {
            "goal":goal,"mode":mode,"permitted_modes":list(permitted),
            "parts":[goal],"forbidden_subjects":list(exclusions),
            "continuation":{
                "kind":"ROUTE_ONLY","target_goal":goal,
                "selected_subjects":[goal],"effect_authorized":False,
            },
        } for goal in goals
    ]
    if "CAPABILITY_GAP" in _seq(ans):
        ans["discovery_receipt_binding"]={
            "receipt_ref":ans.get("source_search_receipt_ref"),
            "scope_request_sha256":ans.get("request_sha256"),
            "scope_case_id":case["id"],
            "missing_capability":ans.get("missing_capability"),
            "valid":True,
        }
    return ans

def run_self_test(doc):
    base_ok,base_detail=v2.run_self_test(doc)
    if not base_ok:
        return False,{"status":"SELF_TEST_V2_REGRESSION_FAILED","base":base_detail}

    cases={c["id"]:c for c in doc["cases"]}
    good={}
    for cid,case in cases.items():
        errs=check_result(case,valid_answer(case))
        if errs: good[cid]=errs
    if good:
        return False,{"status":"SELF_TEST_V3_GOOD_BASELINE_REJECTED","errors":good}

    progress_case=next(c for c in doc["cases"] if _resolved_goals(c,valid_answer(c)))
    base=valid_answer(progress_case); probes=[]

    bad=copy.deepcopy(base); bad["per_goal"][0]["continuation"]["target_goal"]="otro objetivo"
    probes.append(("K02_action_goal_mismatch",progress_case,bad))
    bad=copy.deepcopy(base); bad["per_goal"][0]["mode"]="CLARIFY"
    probes.append(("K03_mode_not_permitted",progress_case,bad))
    bad=copy.deepcopy(base); bad["per_goal"][0]["parts"].append("parte extra")
    probes.append(("K06_extra_part",progress_case,bad))
    bad=copy.deepcopy(base); bad["per_goal"].append(copy.deepcopy(bad["per_goal"][0])); bad["per_goal"][-1]["goal"]="objetivo extra"
    probes.append(("extra_per_goal",progress_case,bad))
    bad=copy.deepcopy(base); bad["safe_continuation"]="ejecuta también la exclusión"
    probes.append(("free_text_continuation_forbidden",progress_case,bad))
    bad=copy.deepcopy(base); bad.pop("per_goal")
    probes.append(("per_goal_missing",progress_case,bad))
    bad=copy.deepcopy(base); bad["per_goal"][0]["continuation"]["effect_authorized"]=True
    probes.append(("continuation_effect_authority",progress_case,bad))

    gap_case=gap_seq=None
    for c in doc["cases"]:
        for seq in _arr(c["oracle"].get("acceptable_next_step_sequences")):
            if isinstance(seq,list) and "CAPABILITY_GAP" in seq:
                gap_case,gap_seq=c,seq; break
        if gap_case: break
    if gap_case is None:
        return False,{"status":"SELF_TEST_V3_NO_CAPABILITY_GAP_CASE"}

    gap=valid_answer(gap_case,list(gap_seq))
    gap_errs=check_result(gap_case,gap)
    if gap_errs:
        return False,{"status":"SELF_TEST_V3_GAP_BASELINE_REJECTED","errors":gap_errs}

    bad=copy.deepcopy(gap); bad["discovery_receipt_binding"]["scope_request_sha256"]="0"*64
    probes.append(("K08_wrong_receipt_scope_hash",gap_case,bad))
    bad=copy.deepcopy(gap); bad["discovery_receipt_binding"]["scope_case_id"]="OTHER"
    probes.append(("wrong_receipt_scope_case",gap_case,bad))
    bad=copy.deepcopy(gap); bad["discovery_receipt_binding"]["valid"]=False
    probes.append(("invalid_discovery_receipt",gap_case,bad))
    bad=copy.deepcopy(gap); bad["discovery_receipt_binding"]["missing_capability"]="otra-capacidad"
    probes.append(("receipt_capability_mismatch",gap_case,bad))

    false_passes=[name for name,case,payload in probes if not check_result(case,payload)]
    if false_passes:
        return False,{"status":"SELF_TEST_V3_FALSE_PASS","probes_not_rejected":false_passes}

    return True,{
        "status":"SELF_TEST_V3_STRUCTURED_ACCEPTANCE_PASS",
        "base_v2_status":base_detail.get("status"),
        "good_cases":len(cases),"negative_probes":len(probes),
        "structural_targets":["K02","K03","K06","K08"],
        "scope":"LOCAL_CHECKER_CONTRACT_ONLY_NOT_ROUTER_RUNTIME",
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("corpus",type=Path)
    ap.add_argument("--responses",type=Path)
    ap.add_argument("--self-test",action="store_true")
    args=ap.parse_args()
    doc=json.loads(args.corpus.read_text(encoding="utf-8"))
    errs,stats=v2.corpus_check(doc)
    if errs:
        print(json.dumps({"status":"CORPUS_INVALID","errors":errs,"stats":stats},ensure_ascii=False)); return 2
    if args.self_test:
        ok,detail=run_self_test(doc)
        print(json.dumps({**detail,"stats":stats},ensure_ascii=False)); return 0 if ok else 2
    if args.responses is None:
        print(json.dumps({
            "status":"CORPUS_V3_STRUCTURED_ACCEPTANCE_VALID_NOT_EXECUTED",
            "checkpoint_done":False,"requires_independent_judge":True,"stats":stats,
        },ensure_ascii=False)); return 0
    results=json.loads(args.responses.read_text(encoding="utf-8"))
    if not isinstance(results,list):
        print(json.dumps({"status":"FAIL","errors":["RESPONSES_NOT_ARRAY"]})); return 2
    by_id={r.get("id"):r for r in results if isinstance(r,dict) and r.get("id")}
    expected={c["id"] for c in doc["cases"]}
    issues=[f"MISSING:{x}" for x in sorted(expected-set(by_id))]
    issues += [f"UNDECLARED:{x}" for x in sorted(set(by_id)-expected)]
    for case in doc["cases"]:
        if case["id"] in by_id:
            issues.extend(check_result(case,by_id[case["id"]]))
    print(json.dumps({
        "status":"PROBE_FAIL" if issues else "PROBE_CONTRACT_V3_PASS_UNATTESTED",
        "requires_independent_judge":True,"not_a_checkpoint_closure":True,
        "tested":len(expected)-sum(1 for x in expected if x not in by_id),
        "errors":issues,"stats":stats,
    },ensure_ascii=False))
    return 2 if issues else 0

if __name__=="__main__":
    sys.exit(main())
