#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json
from pathlib import Path
from typing import Any

ARMS=("A_ORIGINAL","B_UPDATER_V01","C_EVOLUTION_CURRENT","D_EVOLUTION_TARGET")
EVALUATOR_ID="PEXP-R2-DETERMINISTIC-HIDDEN-ORACLE-EVAL-20261008-001"

def canonical_sha(v:Any)->str:
    return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--producer-raw",required=True);ap.add_argument("--tasks",required=True);ap.add_argument("--oracle",required=True)
    ap.add_argument("--campaign",required=True);ap.add_argument("--output",required=True)
    a=ap.parse_args()
    raw=json.loads(Path(a.producer_raw).read_text()); tasks=json.loads(Path(a.tasks).read_text())
    oracle_bytes=Path(a.oracle).read_bytes(); oracle=json.loads(oracle_bytes); campaign=json.loads(Path(a.campaign).read_text())
    if raw.get("raw_frozen") is not True or raw.get("oracle_opened") is not False or raw.get("scoring_opened") is not False:
        raise SystemExit("PRODUCER_RAW_NOT_FROZEN_CLEAN")
    if raw.get("campaign_id")!=campaign.get("campaign_id") or raw.get("campaign_id")!=oracle.get("campaign_id"):
        raise SystemExit("CAMPAIGN_BINDING_MISMATCH")
    om={x["case_id"]:x["correct_choice"] for x in oracle["cases"]}
    tm={x["case_id"]:x for x in tasks["cases"]}
    if set(om)!=set(tm):
        raise SystemExit("ORACLE_TASK_CASE_SET_MISMATCH")
    oracle_sha=hashlib.sha256(oracle_bytes).hexdigest()
    out_cases=[]; receipts=[]
    for c in raw["cases"]:
        cid=c["case_id"]; meta=tm[cid]; arms={}
        for arm in ARMS:
            observed=c["arms"][arm]["choice"]
            score=1.0 if observed==om[cid] else 0.0
            if EVALUATOR_ID==c["arms"][arm]["producer_execution_id"]:
                raise SystemExit("EVALUATOR_NOT_INDEPENDENT")
            receipt={
              "schema":"PROFILE_EXPERT_CASE_EVALUATOR_RECEIPT_V1","campaign_id":raw["campaign_id"],
              "case_id":cid,"producer_execution_id":c["arms"][arm]["producer_execution_id"],
              "evaluator_execution_id":EVALUATOR_ID,"blind_arm":True,"verification_state":"VERIFIED",
              "observed_choice_sha256":hashlib.sha256(observed.encode()).hexdigest(),
              "hidden_oracle_sha256":oracle_sha,"score":score
            }
            receipt["receipt_sha256"]=canonical_sha(receipt); receipts.append(receipt)
            arms[arm]={
              "profile_revision":c["arms"][arm]["profile_revision"],
              "execution_receipt_ref":c["arms"][arm]["execution_receipt_ref"],
              "execution_receipt_sha256":c["arms"][arm]["execution_receipt_sha256"],
              "producer_execution_id":c["arms"][arm]["producer_execution_id"],
              "evaluator_receipt_ref":f"evaluated_raw://{raw['campaign_id']}/{cid}/{arm}",
              "evaluator_verification_state":"VERIFIED",
              "evaluator_execution_id":EVALUATOR_ID,"blind_arm":True,"score":score
            }
        out_cases.append({
          "case_id":cid,"domain_family":meta["domain_family"],"difficulty":meta["difficulty"],
          "critical":meta["critical"],"preservation_case":meta["preservation_case"],
          "adaptation_case":meta["adaptation_case"],"transfer_case":meta["transfer_case"],"arms":arms
        })
    out={
      "schema":"PROFILE_EXPERT_BEHAVIOR_EVALUATED_RAW_V2","campaign_id":raw["campaign_id"],
      "benchmark_scope":"EXPERT_TASK_PERFORMANCE_E2E","raw_frozen":True,"thresholds_frozen_before_raw":True,
      "producer_raw_sha256":hashlib.sha256(Path(a.producer_raw).read_bytes()).hexdigest(),
      "oracle_sha256":oracle_sha,"evaluator_execution_id":EVALUATOR_ID,
      "sample_size_plan":{"planned_case_count":campaign["planned_case_count"],"power_analysis_ref":campaign["power_analysis_ref"]},
      "resource_metrics":raw["resource_metrics"],"cases":out_cases,"evaluator_receipts":receipts,
      "independent_assurance":"NOT_EXECUTED","cutover_eligible":False
    }
    text=json.dumps(out,ensure_ascii=False,indent=2,sort_keys=True)+"\n";Path(a.output).write_text(text)
    print(json.dumps({"status":"PASS","campaign_id":raw["campaign_id"],"case_count":len(out_cases),"evaluator_receipt_count":len(receipts),"evaluated_raw_sha256":hashlib.sha256(text.encode()).hexdigest()},sort_keys=True))
    return 0
if __name__=="__main__": raise SystemExit(main())
