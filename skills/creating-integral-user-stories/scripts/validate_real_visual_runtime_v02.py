#!/usr/bin/env python3
"""Final empirical visual-runtime gate requiring screen-ingestion/v0.2.

Wraps the historical adjudicator but refuses final visual proof unless the
locked blind run also passes the v0.2 multi-pass protocol contract.
"""
from __future__ import annotations
import copy, json
import validate_real_visual_runtime as legacy
from lf_common import ValidationInputError, failure, result_object
import validate_screen_ingestion_v02 as j00

SCHEMA_VERSION="visual-runtime-evidence/v0.2"
_orig=legacy.evaluate_runtime
legacy.SCHEMA_VERSION=SCHEMA_VERSION
legacy.evaluate=j00.evaluate

def evaluate_runtime(blind,reference):
    out=_orig(blind,reference)
    checks,evidence=j00.evaluate(blind)
    eligible=blind.get("schema_version")==j00.V02 and evidence.get("v02_protocol_eligible") is True and all(v==0 for v in checks.values())
    out["schema_version"]=SCHEMA_VERSION
    out["j00"]["v02_protocol_eligible"]=bool(eligible)
    out["j00"]["validation_scope"]=evidence.get("validation_scope")
    if not eligible:
        out["visual_runtime_proven"]=False; out["result"]="RETURN_TO_WORKER"
        if "V02_MULTI_PASS_PROTOCOL_REQUIRED" not in out["blockers"]: out["blockers"].append("V02_MULTI_PASS_PROTOCOL_REQUIRED")
    out["blockers"]=sorted(set(out["blockers"]))
    return out
legacy.evaluate_runtime=evaluate_runtime

def _upgrade(blind):
    blind=copy.deepcopy(blind); blind["schema_version"]=j00.V02
    blind["observation_passes"]=[{"pass_code":c,"status":"COMPLETED","image_refs":[blind["source_images"][0]["image_ref"]],"candidates_added":0,"uncertainty_refs":[]} for c in j00.PASS_SEQUENCE]
    reg=blind["region_inventory"][0]["region_ref"]; img=blind["source_images"][0]["image_ref"]
    blind["visual_observation_inventory"]=[{"observation_code":"OBS-RESP","observation_type":"RESPONSIVE","observability":"NOT_OBSERVABLE","source_ref":f"{img}#RESP","image_ref":img,"region_ref":reg,"semantic_role":"single_viewport_limit","visible_text":None,"visual_value":None,"value_precision":"NOT_APPLICABLE","observation_basis":"VISIBLE_PIXELS","token_relation":"NOT_APPLICABLE","confidence":1.0}]
    blind["coverage_evidence"].update({"omission_scan_completed":True,"consistency_scan_completed":True,"pass_count_completed":7,"visual_candidate_count":1,"structured_visual_candidate_count":1})
    return blind

def self_test():
    blind,ref=legacy.sample(); good=evaluate_runtime(_upgrade(blind),copy.deepcopy(ref)); old=evaluate_runtime(copy.deepcopy(blind),copy.deepcopy(ref))
    bad=_upgrade(blind); bad["context_isolation"]["auxiliary_context_before_lock"]=True; badout=evaluate_runtime(bad,copy.deepcopy(ref))
    cases=[{"case":"positive_v02","passed":good["visual_runtime_proven"] is True},{"case":"legacy_v01_rejected","passed":old["visual_runtime_proven"] is False and "V02_MULTI_PASS_PROTOCOL_REQUIRED" in old["blockers"]},{"case":"isolation_rejected","passed":badout["visual_runtime_proven"] is False}]
    ok=all(x["passed"] for x in cases); print(json.dumps({"self_test_pass":ok,"cases":cases},sort_keys=True)); return 0 if ok else 1
legacy.self_test=self_test

def main(): return legacy.main()
if __name__=="__main__": raise SystemExit(main())
