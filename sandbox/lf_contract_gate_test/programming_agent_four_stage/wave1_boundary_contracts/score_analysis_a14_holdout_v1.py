#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path

def rate(n,d): return 0.0 if d==0 else n/d

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--cases",required=True)
    ap.add_argument("--oracle",required=True)
    ap.add_argument("--candidate",required=True)
    ap.add_argument("--output",required=True)
    args=ap.parse_args()
    cases=json.loads(Path(args.cases).read_text(encoding="utf-8"))
    oracle=json.loads(Path(args.oracle).read_text(encoding="utf-8"))
    cand=json.loads(Path(args.candidate).read_text(encoding="utf-8"))
    if cases.get("schema_version")!="ANALYSIS_A14_FRESH_CASE_SET_V1": raise SystemExit("CASE_SCHEMA_INVALID")
    if oracle.get("schema_version")!="ANALYSIS_A14_FRESH_ORACLE_V1": raise SystemExit("ORACLE_SCHEMA_INVALID")
    if cand.get("schema_version")!="ANALYSIS_A14_CANDIDATE_RESULT_SET_V1": raise SystemExit("CANDIDATE_SCHEMA_INVALID")
    # A14 scores deterministic contract replay, not LLM reasoning or a live PG-01 readback.
    if cand.get("evidence_tier","DETERMINISTIC_CONTRACT_REPLAY")!="DETERMINISTIC_CONTRACT_REPLAY":
        raise SystemExit("A14_EVIDENCE_TIER_MISMATCH")
    if cand.get("model_inference_executed",False) is not False or cand.get("real_programming_consumer_verified",False) is not False:
        raise SystemExit("A14_UNSUPPORTED_RUNTIME_CLAIM")
    if not (cases["case_set_id"]==oracle["case_set_id"]==cand["case_set_id"]): raise SystemExit("CASE_SET_ID_MISMATCH")
    if cases.get("generated_after_candidate_freeze") is not True or cases.get("used_for_A13_tuning") is not False: raise SystemExit("HOLDOUT_VIRGINITY_INVALID")
    o={x["case_id"]:x for x in oracle["oracle"]}
    c={x["case_id"]:x for x in cand["results"]}
    ids=[x["case_id"] for x in cases["cases"]]
    if set(ids)!=set(o) or set(ids)!=set(c): raise SystemExit("CASE_ID_SET_MISMATCH")
    critical_expected=critical_observed=0
    material_expected=material_observed=0
    critical_omitted=0
    false_ready=0
    handoff_ok=0
    lossy_count=0
    class_ok=0
    usable=0
    specialist_failures=[]
    per_case=[]
    for case_id in ids:
        exp=o[case_id]; got=c[case_id]
        ei=set(exp["critical_impacts_expected"]); gi=set(got["critical_impacts_observed"])
        ef=set(exp["material_fronts_expected"]); gf=set(got["material_fronts_observed"])
        omitted=sorted(ei-gi)
        missing_fronts=sorted(ef-gf)
        critical_expected+=len(ei); critical_observed+=len(ei&gi); critical_omitted+=len(omitted)
        material_expected+=len(ef); material_observed+=len(ef&gf)
        expected_blocked=set(exp["blocked_scope_ids_expected"])
        actual_ready=set(got["ready_scope_ids"])
        fr=len(expected_blocked & actual_ready)
        # A handoff mismatch or front-consistency failure blocks ALL downstream
        # admission. Do not allow an oracle to hide a READY scope behind a
        # separately reported negative parity result.
        if got["handoff_parity_verdict"]!="PASS" or got.get("scope_front_consistency_verdict")!="PASS":
            fr+=len(actual_ready - expected_blocked)
        false_ready+=fr
        hp=got["handoff_parity_verdict"]==exp["handoff_parity_expected"]
        handoff_ok+=int(hp)
        if exp.get("lossy_projection_expected_block") and got["handoff_parity_verdict"]!="BLOCK": lossy_count+=1
        class_match=got["depth_level"]==exp["depth_expected"]
        class_ok+=int(class_match)
        # Expected refusal is a successful safe contract outcome. It is not
        # evidence that a real Programming worker consumed the package.
        is_usable=(got["reinterpretation_required"] is False
            and got["schema_version"]=="ANALYSIS_IMPLEMENTATION_PACKAGE_V1"
            and (got["handoff_parity_verdict"]=="PASS" or not actual_ready))
        usable+=int(is_usable)
        expected_refs=set(exp.get("specialist_refs_expected",[]))
        got_refs=set(got.get("specialist_refs",[]))
        if expected_refs!=got_refs: specialist_failures.append(case_id+":SPECIALIST_REFS")
        if exp.get("required_specialist_missing_expected") is True:
            if not got.get("missing_required_specialists") or not set(got["blocked_scope_ids"]): specialist_failures.append(case_id+":REQUIRED_SPECIALIST_NOT_BLOCKED")
        if exp.get("no_specialist_expected") is True and got_refs: specialist_failures.append(case_id+":UNEXPECTED_SPECIALIST")
        per_case.append({
            "case_id":case_id,"critical_omitted":omitted,"material_fronts_missing":missing_fronts,
            "false_ready_count":fr,"depth_match":class_match,"handoff_match":hp,"usable_without_reinterpretation":is_usable
        })
    n=len(ids)
    product_archetypes=len(set(x["archetype"] for x in cases["cases"] if x.get("product_screen_archetype") is True))
    non_screen=sum(1 for x in cases["cases"] if x.get("product_screen_archetype") is not True)
    gates={
        "critical_impacts_omitted":critical_omitted,
        "critical_false_ready":false_ready,
        "material_front_accounting_rate":rate(material_observed,material_expected),
        "handoff_material_parity_rate":rate(handoff_ok,n),
        "lossy_material_projection_count":lossy_count,
        "classification_accuracy":rate(class_ok,n),
        "usable_without_material_reinterpretation":rate(usable,n),
        "fresh_or_unseen_variants":True,
        "minimum_product_screen_archetypes":product_archetypes,
        "non_screen_holdout_count":non_screen,
        "specialist_failure_count":len(specialist_failures)
    }
    passed=(
        critical_omitted==0 and false_ready==0
        and gates["material_front_accounting_rate"]==1.0
        and gates["handoff_material_parity_rate"]==1.0
        and lossy_count==0
        and gates["classification_accuracy"]>=0.95
        and gates["usable_without_material_reinterpretation"]>=0.95
        and product_archetypes>=3 and non_screen>=1 and not specialist_failures
    )
    out={
        "schema_version":"ANALYSIS_A14_FRESH_SCORE_V1",
        "case_set_id":cases["case_set_id"],
        "case_count":n,
        "verdict":"PASS" if passed else "FAIL",
        "gates":gates,
        "specialist_failures":specialist_failures,
        "per_case":per_case,
        "evidence_tier":"DETERMINISTIC_CONTRACT_REPLAY",
        "model_inference_verified":False,
        "real_programming_consumer_verified":False,
        "operational_integration_admissible":False,
        "limits":{
            "model_provider_not_used":True,
            "token_usage":None,
            "elapsed_ms_is_python_replay_not_inference":True,
            "verdict_scope":"CONTRACT_REPLAY_ONLY",
            "model_e2e_and_receiver_readback_required_separately":True
        },
        "runtime_activation":False,"production_activation":False
    }
    Path(args.output).write_text(json.dumps(out,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("PASS_A14_FRESH_VALIDATION" if passed else "FAIL_A14_FRESH_VALIDATION",json.dumps(gates,sort_keys=True))
    raise SystemExit(0 if passed else 1)

if __name__=="__main__": main()
