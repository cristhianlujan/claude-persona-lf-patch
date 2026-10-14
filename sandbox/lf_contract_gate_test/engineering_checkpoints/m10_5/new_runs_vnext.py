#!/usr/bin/env python3
"""M10.5 CP2: evaluate current-source runs; ONB_001 first, full 13 at closeout.
Synthetic self-tests NEVER prove a canonical PASS_CP2.
"""
import argparse
import json
import sys

COUNT = 13
MANDATORY = ("cohort_count", "source_current_count", "validator_assessed_count",
             "technical_pass_count", "cp2_pass_count")
CP2 = {"PASS_CP2", "ERROR_TECNICO", "NO_EJECUCION_VIGENTE", "EN_EVALUACION_NO_ERROR"}
TECHNICAL = {"PASS_TECNICO", "ERROR_TECNICO", "NOT_RUN", "IN_PROGRESS",
             "IN_PROGRESS_OR_POLICY_HOLD", "HOLD_NEEDS_PROVENANCE"}

def classify(data):
    if not isinstance(data, dict) or data.get("schema_version") != "IG_M105_CP2_RELEASE_READBACK_V2":
        return "BLOCK_SCHEMA"
    screens = data.get("screen_results")
    if not isinstance(screens, list) or len(screens) != COUNT:
        return "BLOCK_COHORT"
    if any(not isinstance(x, dict) for x in screens):
        return "BLOCK_SCREEN_SHAPE"
    ids = [x.get("pantalla_id") for x in screens]
    if any(type(x) is not int or x < 1 for x in ids) or len(set(ids)) != COUNT:
        return "BLOCK_SCREEN_IDENTITY"
    if any(x.get("cp2") not in CP2 or x.get("technical") not in TECHNICAL for x in screens):
        return "BLOCK_RESULT_CODE"
    for key in MANDATORY + ("technical_error_count", "cp2_not_current_count",
                            "cp2_pending_count", "semantic_rejections_recorded",
                            "evaluation_holds_recorded", "not_applicable_recorded"):
        if type(data.get(key)) is not int or data[key] < 0:
            return "BLOCK_COUNT_SHAPE"
    if data["cohort_count"] != COUNT:
        return "BLOCK_COHORT_COUNT"
    if data["technical_pass_count"] != sum(x["technical"] == "PASS_TECNICO" for x in screens):
        return "BLOCK_TECHNICAL_COUNT"
    for status, field in (("PASS_CP2", "cp2_pass_count"),
                          ("NO_EJECUCION_VIGENTE", "cp2_not_current_count"),
                          ("EN_EVALUACION_NO_ERROR", "cp2_pending_count")):
        if data[field] != sum(x["cp2"] == status for x in screens):
            return "BLOCK_INCONSISTENT_CP2_COUNT"
    if data["technical_error_count"] or any(x["cp2"] == "ERROR_TECNICO" for x in screens):
        return "BLOCK_REAL_ENGINE_ERROR"
    if data["cp2_pending_count"]:
        return "BLOCK_UNFINISHED_SCREEN_EVALUATION"
    if data["cp2_not_current_count"]:
        return "BLOCK_STALE_OR_NOT_EXECUTED"
    if not isinstance(data.get("current_release"), str) or not data["current_release"]:
        return "BLOCK_CURRENT_RELEASE_IDENTITY"
    if not isinstance(data.get("current_manifest_sha256"), str) or len(data["current_manifest_sha256"]) != 64:
        return "BLOCK_CURRENT_MANIFEST_IDENTITY"
    if data.get("scope_origin") != "M105_SCOPE_SNAPSHOT_V1" or data.get("not_a_production_authorization") is not True:
        return "BLOCK_AUTHORITY_BOUNDARY"
    for key in MANDATORY:
        if data[key] != COUNT:
            return "BLOCK_" + key.upper()
    return "ELIGIBLE_UNATTESTED"

def pilot(data):
    """Reject stale or incomplete pilot even when someone supplies PASS_CP2 text."""
    if not isinstance(data, dict) or data.get("pantalla_id") != 1 or type(data.get("run_id")) is not int or data["run_id"] < 1:
        return "BLOCK_PILOT_IDENTITY"
    if data.get("technical_verdict") != "PASS_TECNICO":
        return "BLOCK_PILOT_TECHNICAL"
    if data.get("source_current") is not True:
        return "BLOCK_PILOT_STALE"
    if (type(data.get("family_count")) is not int or data["family_count"] < 1
        or data.get("final_decisions") != data["family_count"]
        or data.get("invalid_decisions") != 0):
        return "BLOCK_PILOT_COVERAGE"
    if data.get("cp2_verdict") != "PASS_CP2":
        return "BLOCK_PILOT_CANONICAL_VERDICT"
    return "ELIGIBLE_UNATTESTED"

def self_test():
    base = dict(schema_version="IG_M105_CP2_RELEASE_READBACK_V2",
                current_release="1.0.0", previous_release=None,
                current_manifest_sha256="a"*64, scope_origin="M105_SCOPE_SNAPSHOT_V1",
                not_a_production_authorization=True, technical_error_count=0,
                cp2_not_current_count=0, cp2_pending_count=0,
                semantic_rejections_recorded=0, evaluation_holds_recorded=4,
                not_applicable_recorded=0,
                screen_results=[dict(pantalla_id=i,cp2="PASS_CP2",technical="PASS_TECNICO")
                                for i in range(1,COUNT+1)])
    base.update({k: COUNT for k in MANDATORY})
    tests = []
    def check(label, fn, obj, expected):
        actual = fn(obj)
        assert actual == expected, (label, actual, expected)
        tests.append(label)
    check("no new version; cohort logical fixture", classify, base, "ELIGIBLE_UNATTESTED")
    check("missing release identity", classify, dict(base,current_release=""), "BLOCK_CURRENT_RELEASE_IDENTITY")
    check("missing current count", classify, dict(base,source_current_count=12), "BLOCK_SOURCE_CURRENT_COUNT")
    check("duplicate screen", classify, dict(base,screen_results=[base["screen_results"][0]]*COUNT), "BLOCK_SCREEN_IDENTITY")
    stale = [dict(x) for x in base["screen_results"]]
    stale[0]["cp2"]="NO_EJECUCION_VIGENTE"
    check("stale negative", classify, dict(base,screen_results=stale,cp2_pass_count=12,cp2_not_current_count=1), "BLOCK_STALE_OR_NOT_EXECUTED")
    failed = [dict(x) for x in base["screen_results"]]
    failed[0]["cp2"]="ERROR_TECNICO"
    check("real engine error", classify, dict(base,screen_results=failed,cp2_pass_count=12,technical_error_count=1), "BLOCK_REAL_ENGINE_ERROR")
    p = dict(pantalla_id=1,run_id=825,source_current=False,technical_verdict="PASS_TECNICO",
             family_count=47,final_decisions=47,invalid_decisions=0,cp2_verdict="PASS_CP2")
    check("pilot stale negative", pilot, p, "BLOCK_PILOT_STALE")
    check("pilot missing source proof negative", pilot, dict(p,source_current=None), "BLOCK_PILOT_STALE")
    check("pilot missing coverage negative", pilot, dict(p,source_current=True,final_decisions=46), "BLOCK_PILOT_COVERAGE")
    check("pilot valid logical fixture", pilot, dict(p,source_current=True), "ELIGIBLE_UNATTESTED")
    print(json.dumps({"logical_tests":len(tests),"passed":len(tests),
                      "material_cp2_pass":False,"tests":tests},sort_keys=True))

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--self-test",action="store_true")
    parser.add_argument("--readback")
    parser.add_argument("--pilot",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if not args.readback: parser.error("--readback required")
        with open(args.readback,encoding="utf-8") as fh: data=json.load(fh)
        verdict=pilot(data) if args.pilot else classify(data)
        print(verdict)
        sys.exit(3 if verdict=="ELIGIBLE_UNATTESTED" else 2)
