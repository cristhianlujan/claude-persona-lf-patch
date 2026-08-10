#!/usr/bin/env python3
"""Final empirical visual-runtime gate requiring screen-ingestion/v0.2.

Wraps the historical adjudicator but refuses final visual proof unless the
locked blind run also passes the v0.2 multi-pass protocol contract. v0.2 also
adjudicates deep visual observations without changing the legacy v0.1 reader.
"""
from __future__ import annotations
import copy, json
import validate_real_visual_runtime as legacy
from lf_common import ValidationInputError, failure, result_object
import validate_screen_ingestion_v02 as j00

SCHEMA_VERSION="visual-runtime-evidence/v0.2"
_orig=legacy.evaluate_runtime
_orig_observed_texts=legacy.observed_texts
legacy.SCHEMA_VERSION=SCHEMA_VERSION
legacy.evaluate=j00.evaluate

def observed_texts(blind):
    values=list(_orig_observed_texts(blind))
    for item in blind.get("visual_observation_inventory",[]):
        if not isinstance(item,dict):
            continue
        for key in ("visible_text","visual_value"):
            value=item.get(key)
            if value is not None and str(value).strip():
                values.append(str(value))
    return values

legacy.observed_texts=observed_texts

def evaluate_runtime(blind,reference):
    out=_orig(blind,reference)
    checks,evidence=j00.evaluate(blind)
    eligible=blind.get("schema_version")==j00.V02 and evidence.get("v02_protocol_eligible") is True and all(v==0 for v in checks.values())
    out["schema_version"]=SCHEMA_VERSION
    out["j00"]["v02_protocol_eligible"]=bool(eligible)
    out["j00"]["validation_scope"]=evidence.get("validation_scope")
    out["j00"]["visual_observation_count"]=evidence.get("visual_observation_count")
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
    blind,ref=legacy.sample()
    good=evaluate_runtime(_upgrade(blind),copy.deepcopy(ref))
    old=evaluate_runtime(copy.deepcopy(blind),copy.deepcopy(ref))
    bad=_upgrade(blind); bad["context_isolation"]["auxiliary_context_before_lock"]=True
    badout=evaluate_runtime(bad,copy.deepcopy(ref))

    deep=_upgrade(blind)
    deep["region_inventory"][0]["description"]="No legacy match"
    deep["context_inventory"][0]["description"]="No legacy match"
    deep["field_inventory"][0]["visible_label"]="No legacy match"
    img=deep["source_images"][0]["image_ref"]; reg=deep["region_inventory"][0]["region_ref"]
    deep["visual_observation_inventory"].append({
        "observation_code":"OBS-DEEP-ACTION","observation_type":"COPY","observability":"OBSERVED",
        "source_ref":f"{img}#DEEP-ACTION","image_ref":img,"region_ref":reg,
        "semantic_role":"deep_action","visible_text":"Deep Only Action","visual_value":None,
        "value_precision":"SEMANTIC_ONLY","observation_basis":"VISIBLE_TEXT",
        "token_relation":"NOT_APPLICABLE","confidence":1.0
    })
    deep["coverage_evidence"]["visual_candidate_count"]=2
    deep["coverage_evidence"]["structured_visual_candidate_count"]=2
    deep_ref=copy.deepcopy(ref)
    deep_ref["fixture"]["observed_screen"]["actions"]=[{"code":"ACT-DEEP","visible_text":"Deep Only Action"}]
    deep_ref["fixture"]["observed_screen"]["fields"]=[]
    deepout=evaluate_runtime(deep,deep_ref)

    cases=[
      {"case":"positive_v02","passed":good["visual_runtime_proven"] is True},
      {"case":"legacy_v01_rejected","passed":old["visual_runtime_proven"] is False and "V02_MULTI_PASS_PROTOCOL_REQUIRED" in old["blockers"]},
      {"case":"isolation_rejected","passed":badout["visual_runtime_proven"] is False},
      {"case":"deep_visual_observation_adjudicated","passed":deepout["visual_runtime_proven"] is True and deepout["benchmark"]["omission_count"]==0},
    ]
    ok=all(x["passed"] for x in cases)
    print(json.dumps({"self_test_pass":ok,"cases":cases},sort_keys=True))
    return 0 if ok else 1
legacy.self_test=self_test

def main(): return legacy.main()
if __name__=="__main__": raise SystemExit(main())
