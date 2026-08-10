#!/usr/bin/env python3
"""Versioned v0.2 protocol wrapper for the legacy J00 screen-ingestion validator.

Keeps v0.1 structural behavior intact while adding multi-pass, deep visual
provenance, omission-accounting, and single-viewport responsive guards.
"""
from __future__ import annotations
import copy, json
from pathlib import Path
from typing import Any
import validate_screen_ingestion as legacy

VERSION = "v0.2"
V02 = "screen-ingestion/v0.2"
PASS_SEQUENCE = ("MACRO_STRUCTURE","FUNCTIONAL_CONTROLS","MICROCOPY","VISUAL_CHARACTERISTICS","RESPONSIVE","ADVERSARIAL_OMISSION","CONSISTENCY")
EXTRA = ("observation_pass_sequence","visual_observation_refs_resolvable","candidate_accounting_consistent","visual_provenance_safe","single_viewport_responsive_safe")
_orig_evaluate = legacy.evaluate
legacy.VERSION = VERSION
legacy.ASSERTIONS = (*legacy.ASSERTIONS, *EXTRA)

def evaluate(value: dict[str, Any]):
    checks, evidence = _orig_evaluate(value)
    is_v02 = value.get("schema_version") == V02
    images = [x for x in value.get("source_images",[]) if isinstance(x,dict)]
    regions = [x for x in value.get("region_inventory",[]) if isinstance(x,dict)]
    obs = [x for x in value.get("visual_observation_inventory",[]) if isinstance(x,dict)]
    passes = [x for x in value.get("observation_passes",[]) if isinstance(x,dict)]
    image_refs = {str(x.get("image_ref")) for x in images if x.get("image_ref")}
    region_refs = {str(x.get("region_ref")) for x in regions if x.get("region_ref")}
    visual_refs, ref_errors, provenance_errors, responsive_errors = [], 0, 0, 0
    single_viewport = len({(x.get("width_px"),x.get("height_px")) for x in images}) <= 1
    for item in obs:
        if item.get("image_ref") not in image_refs or item.get("region_ref") not in region_refs: ref_errors += 1
        ref = str(item.get("source_ref") or "").strip()
        if ref: visual_refs.append(ref)
        if item.get("token_relation") not in {"NOT_APPLICABLE","CANDIDATE_ONLY","UNRESOLVED_REGISTRY"}: provenance_errors += 1
        if item.get("observation_type") == "TYPOGRAPHY_APPEARANCE" and item.get("value_precision") == "EXACT_DECLARED" and item.get("observation_basis") != "DECLARED_SOURCE_METADATA": provenance_errors += 1
        if single_viewport and item.get("observation_type") == "RESPONSIVE" and item.get("observability") != "NOT_OBSERVABLE": responsive_errors += 1
    coverage = value.get("coverage_evidence") if isinstance(value.get("coverage_evidence"),dict) else {}
    pass_errors = accounting_errors = 0
    if is_v02:
        if tuple(x.get("pass_code") for x in passes) != PASS_SEQUENCE or any(x.get("status") != "COMPLETED" for x in passes): pass_errors += 1
        if any(set(x.get("image_refs") or []) != image_refs for x in passes): pass_errors += 1
        if coverage.get("omission_scan_completed") is not True or coverage.get("consistency_scan_completed") is not True: pass_errors += 1
        if coverage.get("pass_count_completed") != len(PASS_SEQUENCE): pass_errors += 1
        if coverage.get("visual_candidate_count") != len(obs): accounting_errors += 1
        if coverage.get("structured_visual_candidate_count") != len(obs): accounting_errors += 1
        ref_errors += len(visual_refs)-len(set(visual_refs))
    checks.update({"observation_pass_sequence":pass_errors,"visual_observation_refs_resolvable":ref_errors,"candidate_accounting_consistent":accounting_errors,"visual_provenance_safe":provenance_errors,"single_viewport_responsive_safe":responsive_errors})
    evidence.update({"schema_version_observed":value.get("schema_version"),"visual_observation_count":len(obs),"pass_sequence_expected":list(PASS_SEQUENCE),"single_viewport":single_viewport,"v02_protocol_eligible":is_v02 and all(checks.get(k,1)==0 for k in legacy.ASSERTIONS),"visual_runtime_proven":False,"validation_scope":"STRUCTURAL_AND_BLIND_PROTOCOL_CONTRACT","checks":checks})
    return checks, evidence

legacy.evaluate = evaluate

def self_test() -> int:
    root = Path(__file__).resolve().parent.parent
    good = legacy.load_json(root/"evals/fixtures/screen_ingestion_dense.json")
    cases=[]
    def run(name, mutate, expected_fail=None):
        x=copy.deepcopy(good); mutate(x); out=legacy.build(x,[f"self-test://{name}"],None,legacy.canonical_sha(x)); failed=set(out.get("failed_assertions") or [])
        ok=(out["result"]==("PASS_WITH_EVIDENCE" if expected_fail is None else "RETURN_TO_WORKER") and (expected_fail is None or expected_fail in failed)); cases.append({"case":name,"result":out["result"],"failed":sorted(failed),"passed":ok})
    run("positive",lambda x:None)
    run("omission_scan_missing",lambda x:x["coverage_evidence"].__setitem__("omission_scan_completed",False),"input_schema_valid")
    run("pass_order",lambda x:x["observation_passes"].reverse(),"observation_pass_sequence")
    run("candidate_accounting",lambda x:x["coverage_evidence"].__setitem__("visual_candidate_count",0),"candidate_accounting_consistent")
    x=copy.deepcopy(good); x["visual_observation_inventory"].append({"observation_code":"OBS-FONT","observation_type":"TYPOGRAPHY_APPEARANCE","observability":"OBSERVED","source_ref":"IMG-001#FONT","image_ref":"IMG-001","region_ref":"REG-SEARCH","semantic_role":"font","visible_text":None,"visual_value":"Inter","value_precision":"EXACT_DECLARED","observation_basis":"VISIBLE_PIXELS","token_relation":"CANDIDATE_ONLY","confidence":.7}); x["coverage_evidence"]["visual_candidate_count"]=len(x["visual_observation_inventory"]); x["coverage_evidence"]["structured_visual_candidate_count"]=len(x["visual_observation_inventory"]); out=legacy.build(x,["self-test://font"],None,legacy.canonical_sha(x)); cases.append({"case":"exact_font","passed":"visual_provenance_safe" in set(out.get("failed_assertions") or [])})
    x=copy.deepcopy(good); next(o for o in x["visual_observation_inventory"] if o["observation_type"]=="RESPONSIVE")["observability"]="INFERRED"; out=legacy.build(x,["self-test://responsive"],None,legacy.canonical_sha(x)); cases.append({"case":"single_viewport_responsive","passed":"single_viewport_responsive_safe" in set(out.get("failed_assertions") or [])})
    legacy_v01=legacy.positive_fixture(); out=legacy.build(legacy_v01,["self-test://legacy"],None,legacy.canonical_sha(legacy_v01)); cases.append({"case":"legacy_v01_structural_only","passed":out["result"]=="PASS_WITH_EVIDENCE" and out["evidence"].get("v02_protocol_eligible") is False})
    ok=all(c["passed"] for c in cases); print(json.dumps({"judge_code":legacy.JUDGE,"version":VERSION,"self_test_pass":ok,"cases":cases},sort_keys=True)); return 0 if ok else 1

legacy.self_test = self_test

def main(): return legacy.main()
if __name__ == "__main__": raise SystemExit(legacy.main_guard(legacy.JUDGE, main))
