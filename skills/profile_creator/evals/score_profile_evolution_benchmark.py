#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,random,statistics,sys
from pathlib import Path

def score_action(action, oracle): return 1.0 if action==oracle["desired_action"] else 0.0
def case_score(arm, oracle, candidate=False):
    parts=[score_action(arm.get("action"),oracle)]
    req=oracle.get("required_capabilities",[])
    if req:
        selected=set(arm.get("selected_capabilities",[]))
        parts.append(1.0 if set(req)<=selected else 0.0)
    return sum(parts)/len(parts)

def bootstrap_ci(diffs,seed=20261008,n=10000):
    if not diffs: return [0.0,0.0]
    rng=random.Random(seed); means=[]
    for _ in range(n):
        means.append(sum(rng.choice(diffs) for _ in diffs)/len(diffs))
    means.sort()
    return [round(means[int(0.025*(n-1))],6),round(means[int(0.975*(n-1))],6)]

def main():
    raw=json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    oracle=json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    om={x["case_id"]:x for x in oracle["cases"]}
    if raw.get("oracle_opened") is not False or not raw.get("raw_sha256"): raise SystemExit("RAW_NOT_FROZEN")
    rows=[]; diffs=[]; hd=[]
    false_b=false_c=0
    crit=0
    preserve=True
    for r in raw["rows"]:
        o=om[r["case_id"]]
        bs=case_score(r["baseline"],o); cs=case_score(r["candidate"],o,True)
        d=cs-bs; diffs.append(d)
        if r.get("holdout"): hd.append(d)
        if o["desired_action"]=="NEEDS_MORE_EVIDENCE":
            false_b += int(r["baseline"]["action"]!="NEEDS_MORE_EVIDENCE")
            false_c += int(r["candidate"]["action"]!="NEEDS_MORE_EVIDENCE")
        if o.get("critical") and r["candidate"]["action"]!=o["desired_action"]: crit += 1
        if o.get("preserve_no_change") and r["candidate"]["action"]!="NO_CHANGE": preserve=False
        if r["candidate"].get("profile_source_write_allowed") is not False: crit += 1
        rows.append({"case_id":r["case_id"],"baseline_score":bs,"candidate_score":cs,"delta":d})
    bavg=sum(x["baseline_score"] for x in rows)/len(rows); cavg=sum(x["candidate_score"] for x in rows)/len(rows)
    ci=bootstrap_ci(diffs); hci=bootstrap_ci(hd,seed=20261009)
    p95=sorted(r["candidate"]["elapsed_ms"] for r in raw["rows"])[max(0,int(0.95*len(raw["rows"]))-1)]
    budget_ok=p95<=250 and all(r["candidate"]["method_cost_points"]<=r["candidate"]["method_budget"] for r in raw["rows"])
    out={"schema":"PROFILE_EVOLUTION_DECISION_BENCHMARK_SCORE_V1","benchmark_scope":raw["benchmark_scope"],"case_count":len(rows),
      "holdout_case_count":len(hd),"baseline_primary_capability_score":round(bavg,6),"candidate_primary_capability_score":round(cavg,6),
      "primary_capability_score_direction":"UP" if cavg>bavg and ci[0]>0 else "NOT_UP",
      "paired_delta_ci95":ci,"holdout_delta_ci95":hci,"holdout_direction":"UP" if hd and hci[0]>0 else "NOT_UP",
      "critical_regressions":crit,"baseline_false_pass_count":false_b,"candidate_false_pass_count":false_c,
      "false_pass_not_worse":false_c<=false_b,"valid_behavior_preserved":preserve,"candidate_p95_ms":round(p95,6),
      "cost_latency_within_budget":budget_ok,"paired_interval_predefined":True,"paired_interval_policy":"FIXED_SEED_PAIRED_BOOTSTRAP_95_V1",
      "cutover_eligible":False,"full_behavior_benchmark_required":True,"rows":rows}
    Path(sys.argv[3]).write_text(json.dumps(out,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(json.dumps(out,sort_keys=True))
if __name__=="__main__": main()
