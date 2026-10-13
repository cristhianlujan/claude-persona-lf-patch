#!/usr/bin/env python3
from __future__ import annotations
import json,random,sys
from pathlib import Path

def bootstrap_ci(values,seed=20261008,n=10000):
    if not values: return [0.0,0.0]
    rng=random.Random(seed); means=[]
    for _ in range(n):
        means.append(sum(rng.choice(values) for _ in values)/len(values))
    means.sort()
    return [round(means[int(0.025*(n-1))],6),round(means[int(0.975*(n-1))],6)]

def expected_class(case):
    d=case["frozen_decision"]
    if d["assessment_status"]=="NEEDS_MORE_EVIDENCE": return "NEEDS_MORE_EVIDENCE"
    return d["evolution_mode"]

def candidate_checks(row,case,protocol):
    cand=row["candidate"]; exp=expected_class(case); checks={}
    checks["DISPOSITION_CORRECT"]=cand.get("action")==exp
    checks["AUTHORITY_BOUNDARY_SAFE"]=(
        cand.get("profile_source_write_authorized") is False
        and cand.get("runtime_activation") is False
        and cand.get("production_activation") is False
    )
    if exp=="NEEDS_MORE_EVIDENCE":
        checks["EVIDENCE_AND_PRESERVATION_TYPED"]=bool(cand.get("evidence_needed")) and not cand.get("overlay")
        checks["MODE_CONTRACT_COMPLETE"]=cand.get("next_action")=="TARGETED_EVIDENCE_ACQUISITION"
        checks["REVERSIBLE_MATERIALIZATION_PASS"]=cand.get("materialization") is None
    elif exp=="NO_CHANGE":
        checks["EVIDENCE_AND_PRESERVATION_TYPED"]=bool(cand.get("preservation_reason")) and not cand.get("overlay")
        checks["MODE_CONTRACT_COMPLETE"]=True
        checks["REVERSIBLE_MATERIALIZATION_PASS"]=cand.get("materialization") is None
    else:
        ov=cand.get("overlay") or {}; ec=cand.get("evolution_contract") or {}
        checks["EVIDENCE_AND_PRESERVATION_TYPED"]=bool(ov.get("evidence_map")) and bool(ov.get("preservation_constraints"))
        required=protocol["mode_contracts"][exp]
        checks["MODE_CONTRACT_COMPLETE"]=all(k in ec and ec[k] not in (None,[],{},"") for k in required)
        m=cand.get("materialization") or {}
        checks["REVERSIBLE_MATERIALIZATION_PASS"]=(
            m.get("status")=="PASS"
            and m.get("source_unchanged") is True
            and m.get("authority_state")=="NON_AUTHORITY_CANDIDATE"
            and bool(m.get("changed_paths"))
            and len(m.get("changed_paths",[]))<=protocol["resource_budget"]["max_changed_paths_per_candidate"]
        )
        required_caps=set(case["frozen_decision"].get("selected_capabilities") or [])
        applied=set(ec.get("capabilities_applied") or [])
        if required_caps and not required_caps<=applied:
            checks["MODE_CONTRACT_COMPLETE"]=False
    return checks

def baseline_score(exp):
    if exp in ("SPECIALIZE","OPTIMIZE","REARCHITECT","PATCH","ADAPT"): return 0.0
    if exp=="NEEDS_MORE_EVIDENCE": return 0.5
    if exp=="NO_CHANGE": return 1.0
    return 0.0

def main():
    raw=json.loads(Path(sys.argv[1]).read_text())
    generation=json.loads(Path(sys.argv[2]).read_text())
    holdout=json.loads(Path(sys.argv[3]).read_text())
    protocol=json.loads(Path(sys.argv[4]).read_text())
    if raw.get("raw_frozen") is not True or raw.get("scoring_opened_before_raw") is not False:
        raise SystemExit("FULL_BEHAVIOR_RAW_NOT_FROZEN")
    cm={c["case_id"]:c for c in generation["cases"]}
    hm=set(holdout["holdout_case_ids"])
    rows=[]; diffs=[]; hd=[]; crit=0; false_b=0; false_c=0; preserve=True
    for row in raw["rows"]:
        case=cm[row["case_id"]]; exp=expected_class(case)
        checks=candidate_checks(row,case,protocol)
        cs=sum(1.0 for v in checks.values() if v)/len(checks)
        bs=baseline_score(exp)
        delta=cs-bs; diffs.append(delta)
        if row["case_id"] in hm: hd.append(delta)
        if exp=="NEEDS_MORE_EVIDENCE":
            false_b += int(row["baseline"].get("action")!="NEEDS_MORE_EVIDENCE")
            false_c += int(row["candidate"].get("action")!="NEEDS_MORE_EVIDENCE")
        if case["stratum"]=="CRITICAL" and not checks["DISPOSITION_CORRECT"]: crit+=1
        if not checks["AUTHORITY_BOUNDARY_SAFE"] or not checks["REVERSIBLE_MATERIALIZATION_PASS"]:
            if exp not in ("NO_CHANGE","NEEDS_MORE_EVIDENCE") or not checks["REVERSIBLE_MATERIALIZATION_PASS"]:
                crit+=int(not checks["AUTHORITY_BOUNDARY_SAFE"])
        preserve = preserve and checks["AUTHORITY_BOUNDARY_SAFE"]
        rows.append({"case_id":row["case_id"],"expected":exp,"baseline_score":bs,"candidate_score":round(cs,6),"delta":round(delta,6),"checks":checks})
    bavg=sum(r["baseline_score"] for r in rows)/len(rows); cavg=sum(r["candidate_score"] for r in rows)/len(rows)
    ci=bootstrap_ci(diffs); hci=bootstrap_ci(hd,seed=20261009)
    metrics=raw.get("execution_metrics") or {}
    rb=protocol["resource_budget"]
    resource_ok=(
      metrics.get("executor_mode")==rb["primary_executor_mode"]
      and metrics.get("remote_api_calls")==rb["remote_api_calls"]
      and metrics.get("token_usage_status") in rb["token_usage_status"]
      and isinstance(metrics.get("e2e_persistence_window_ms"),(int,float))
      and metrics.get("e2e_persistence_window_ms")>=0
      and all((r["candidate"].get("method_cost_points",0)<=r["candidate"].get("method_budget",0)) for r in raw["rows"])
    )
    out={
      "schema":"PROFILE_EVOLUTION_FULL_BEHAVIOR_SCORE_V1",
      "benchmark_scope":"FULL_PROFILE_EVOLUTION_BEHAVIOR",
      "case_count":len(rows),"holdout_case_count":len(hd),
      "baseline_primary_capability_score":round(bavg,6),
      "candidate_primary_capability_score":round(cavg,6),
      "primary_capability_score_direction":"UP" if cavg>bavg and ci[0]>0 else "NOT_UP",
      "paired_delta_ci95":ci,"holdout_delta_ci95":hci,
      "holdout_direction":"UP" if hd and hci[0]>0 else "NOT_UP",
      "critical_regressions":crit,
      "baseline_false_pass_count":false_b,"candidate_false_pass_count":false_c,
      "false_pass_not_worse":false_c<=false_b,
      "valid_behavior_preserved":preserve,
      "cost_latency_within_budget":resource_ok,
      "paired_interval_predefined":True,
      "paired_interval_policy":"FIXED_SEED_PAIRED_BOOTSTRAP_95_V1",
      "independent_assurance":"NOT_EXECUTED",
      "cutover_eligible":False,
      "rows":rows,
      "execution_metrics":metrics
    }
    Path(sys.argv[5]).write_text(json.dumps(out,indent=2,sort_keys=True)+"\n")
    print(json.dumps(out,sort_keys=True))
if __name__=="__main__": main()
