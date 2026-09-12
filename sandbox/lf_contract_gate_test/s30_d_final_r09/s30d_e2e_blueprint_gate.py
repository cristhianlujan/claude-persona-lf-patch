#!/usr/bin/env python3
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
HERE=Path(__file__).resolve().parent
def load(n): return json.loads((HERE/n).read_text(encoding="utf-8"))
def validate():
 e=load("e2e_campaign_blueprint_v1.json"); r=load("e2e_result_contract_v1.json"); n=load("data_navigation_trace_blueprint_v1.json")
 failures=[]; counts=Counter(x.get("family") for x in e.get("cases",[]))
 if e.get("case_count")!=50 or len(e.get("cases",[]))!=50: failures.append("E2E_CASE_COUNT")
 if len(counts)!=10 or set(counts.values())!={5}: failures.append("E2E_FAMILY_DISTRIBUTION")
 if len({x.get("case_id") for x in e.get("cases",[])})!=50: failures.append("E2E_DUPLICATE_IDS")
 for c in e.get("cases",[]):
  if set(c.get("dimensions",{}))!={"functionality","depth","performance","quality"}: failures.append("E2E_DIMENSIONS:"+str(c.get("case_id"))); break
  if c.get("cross_metrics",{}).get("avoidable_work_target")!=0: failures.append("E2E_AVOIDABLE_WORK_TARGET"); break
 if r.get("quality",{}).get("producer_self_verdict_allowed") is not False: failures.append("SELF_VERDICT_ALLOWED")
 if n.get("execution_prerequisite")!="S30_INTEGRATED_E2E_50_PASS": failures.append("NAV_PREMATURE")
 return {"interface":"S30_E2E_BLUEPRINT_GATE_V1","status":"PASS_BLUEPRINT" if not failures else "BLOCKED","execution_allowed":False,"case_count":50,"families":10,"cases_per_family":5,"failures":failures,"model_calls":0,"next_after_e2e":"ONE_BY_ONE_DATA_NAVIGATION_TRACE"}
if __name__=="__main__": print(json.dumps(validate(),sort_keys=True))
