#!/usr/bin/env python3
"""M10.5 CP2: ONE screen, FIVE contrasting family strata.
Review an authentic provider readback. A fixture is NEVER a material PASS.
The old filename is preserved only for checkpoint reference compatibility.
"""
import argparse
import json
import sys

SAMPLE_FAMILIES = {
    "STATES", "SECURITY", "API_DATA_CONTRACT",
    "FRESHNESS_INVALIDATION", "ACCESSIBILITY"
}

def classify(d):
    if not isinstance(d, dict) or d.get("schema_version") != "IG_M105_CP2_SAMPLE_READBACK_V1":
        return "BLOCK_SCHEMA"
    if (type(d.get("sample_screen_id")) is not int or d["sample_screen_id"] != 1
            or type(d.get("sample_run_id")) is not int or d["sample_run_id"] <= 0):
        return "BLOCK_PILOT_IDENTITY"
    if d.get("authorizes_production") is not False:
        return "BLOCK_PRODUCTION_AUTHORITY"
    if d.get("run_status") != "COMPLETED":
        return "BLOCK_UNFINISHED_RUN"
    if d.get("source_current") is not True:
        return "BLOCK_STALE"
    if d.get("stale_negative_verified") is not True:
        return "BLOCK_MISSING_REAL_NEGATIVE"
    if d.get("sampled_screen_count") != 1:
        return "BLOCK_WRONG_SCREEN_SCOPE"
    if d.get("sample_family_count") != 5 or d.get("valid_family_count") != 5:
        return "BLOCK_SAMPLE_COVERAGE"
    families = d.get("sample_families")
    if (not isinstance(families, list) or len(families) != 5
            or {f.get("family") for f in families if isinstance(f, dict)} != SAMPLE_FAMILIES):
        return "BLOCK_SAMPLE_STRATA"
    if any(not isinstance(f, dict) or f.get("valid_evidence") is not True
           or f.get("validation") not in ("PASS","FAIL","BLOCKED")
           for f in families):
        return "BLOCK_INDEPENDENT_VALIDATOR_EVIDENCE"
    if d.get("sample_verdict") != "PASS_CP2_MUESTRA":
        return "BLOCK_CANONICAL_SAMPLE_VERDICT"
    return "ELIGIBLE_UNATTESTED"

def logical_tests():
    examples = [
        {"slot":code.lower(), "family":code,
         "validation":"PASS","coverage":"COMPLETE","valid_evidence":True}
        for code in sorted(SAMPLE_FAMILIES)
    ]
    good = dict(schema_version="IG_M105_CP2_SAMPLE_READBACK_V1",
                sample_screen_id=1,sample_run_id=931,sampled_screen_count=1,
                sample_family_count=5,valid_family_count=5,
                run_status="COMPLETED",source_current=True,
                stale_negative_verified=True,authorizes_production=False,
                sample_families=examples,sample_verdict="PASS_CP2_MUESTRA")
    cases = [
        ("valid_sample_fixture",good,"ELIGIBLE_UNATTESTED"),
        ("reject_other_screen",dict(good,sample_screen_id=2),"BLOCK_PILOT_IDENTITY"),
        ("reject_missing_run",dict(good,sample_run_id=None),"BLOCK_PILOT_IDENTITY"),
        ("reject_production",dict(good,authorizes_production=True),"BLOCK_PRODUCTION_AUTHORITY"),
        ("reject_unfinished",dict(good,run_status="VALIDATING"),"BLOCK_UNFINISHED_RUN"),
        ("reject_stale",dict(good,source_current=False),"BLOCK_STALE"),
        ("reject_no_negative",dict(good,stale_negative_verified=False),"BLOCK_MISSING_REAL_NEGATIVE"),
        ("reject_13_screen",dict(good,sampled_screen_count=13),"BLOCK_WRONG_SCREEN_SCOPE"),
        ("reject_47_family",dict(good,sample_family_count=47),"BLOCK_SAMPLE_COVERAGE"),
        ("reject_missing_family",dict(good,valid_family_count=4),"BLOCK_SAMPLE_COVERAGE"),
        ("reject_wrong_strata",dict(good,sample_families=examples[:4] + [
            dict(examples[-1],family="OTHER")]),"BLOCK_SAMPLE_STRATA"),
        ("reject_invalid_validator",dict(good,sample_families=[
            dict(f,valid_evidence=False) if f["family"]=="SECURITY" else f for f in examples]),
            "BLOCK_INDEPENDENT_VALIDATOR_EVIDENCE"),
        ("reject_textual_false_pass",dict(good,sample_verdict="NOT_EXECUTED"),"BLOCK_CANONICAL_SAMPLE_VERDICT")
    ]
    for name,case,expected in cases:
        observed = classify(case)
        if observed != expected:
            raise AssertionError(f"{name}: {observed} != {expected}")
    print(json.dumps({"logical_tests_passed":len(cases),
                      "real_run_executed":False,
                      "material_pass_certified":False}))

if __name__ == "__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--self-test",action="store_true")
    p.add_argument("--readback")
    args=p.parse_args()
    if args.self_test:
        logical_tests()
    else:
        if not args.readback:
            p.error("--readback is required")
        with open(args.readback,encoding="utf-8") as f:
            data=json.load(f)
        verdict=classify(data)
        print(verdict)
        sys.exit(3 if verdict=="ELIGIBLE_UNATTESTED" else 2)
