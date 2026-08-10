#!/usr/bin/env python3
from __future__ import annotations
import copy, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
from validate_p0_machine_visual_quality import derive, sha256_value, LEGACY_BAD_SHA
from build_p0_review_evidence_packet_v3 import build
SOURCE="e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
def good():
    consolidated={"schema_version":"p0-consolidated-visual-reading/v1","execution_id":"reader-1","source_image_refs":["IMG-1"],"source_sha256":SOURCE,
      "elements":[
       {"element_id":"ROOT","source_image_ref":"IMG-1","parent_id":None,"region":{"x":0,"y":0,"width":100,"height":100},"element_type":"SCREEN","visible_text":None,"semantic_role":"screen","visual_state":"STATIC","classification":"CONFIRMED","confidence":1.0,"evidence_refs":["source://1"],"source_observation_refs":[],"uncertainty_codes":[],"machine_resolution_status":"RESOLVED"},
       {"element_id":"FORM","source_image_ref":"IMG-1","parent_id":"ROOT","region":{"x":5,"y":5,"width":90,"height":80},"element_type":"CONTAINER","visible_text":None,"semantic_role":"form","visual_state":"STATIC","classification":"CONFIRMED","confidence":.99,"evidence_refs":["crop://form"],"source_observation_refs":["o1"],"uncertainty_codes":[],"machine_resolution_status":"RESOLVED"},
       {"element_id":"BTN","source_image_ref":"IMG-1","parent_id":"FORM","region":{"x":20,"y":70,"width":60,"height":10},"element_type":"BUTTON","visible_text":"Continuar","semantic_role":"primary_action","visual_state":"ENABLED","classification":"CONFIRMED","confidence":.98,"evidence_refs":["crop://btn"],"source_observation_refs":["o2"],"uncertainty_codes":[],"machine_resolution_status":"RESOLVED"}],
      "ui_structure":{"visual_containment_tree":{"roots":["ROOT"],"edges":[{"parent":"ROOT","child":"FORM"},{"parent":"FORM","child":"BTN"}]},"visual_layer_graph":[],"candidate_reading_orders":[["FORM","BTN"]]},"created_at":"2026-08-10T16:00:00Z"}
    csha=sha256_value(consolidated)
    report={"schema_version":"p0-machine-visual-quality-report/v1","execution_id":"quality-1","source_image_refs":["IMG-1"],"source_sha256":SOURCE,
      "raw_visual_output_sha256":"1"*64,"consolidated_visual_reading_sha256":csha,"p0h_execution_id":"p0h-1","j00_execution_id":"j00-1","j00_identity":"P0_VISUAL_JUDGE","remediation_cycles":1,"max_remediation_cycles":3,
      "counts":{"consolidated_elements":3,"confirmed":3,"inferred":0,"not_observable":0,"audit_only":0,"reader_only":0,"contradictions":0,"unsupported_claims":0,"critical_omissions":0,"noncritical_omissions":0,"unresolved_critical_uncertainties":0,"pending_remediations":0},
      "checks":{k:True for k in ("evidence_integrity_pass","visual_structure_pass","visual_semantic_pass","visual_completeness_pass","source_admission_binding_pass","j00_independence_pass","security_pass","privacy_pass","model_configuration_registered","calibration_policy_current","packet_hashes_reconcilable")},
      "result":"PASS_VISUAL_QUALITY","human_review_ready":True,"blocking_assertions":[],"created_at":"2026-08-10T16:00:00Z","model_configuration_id":"modelcfg-1","calibration_reference":"cal-1"}
    judge={"execution_id":"j00-1","identity":"P0_VISUAL_JUDGE","source_sha256":SOURCE,"candidate_sha256":csha,"judgment":"PASS"}
    return consolidated,report,judge
def blocked(mutator):
    c,r,j=good(); mutator(c,r,j); return not derive(r,c,j)["human_review_ready"]
tests={}
c,r,j=good(); tests["P01_positive_canonical"]=derive(r,c,j)["human_review_ready"] is True
tests["N01_legacy_ocr_only"]=blocked(lambda c,r,j:r.update(raw_visual_output_sha256=LEGACY_BAD_SHA))
tests["N02_missing_p0h"]=blocked(lambda c,r,j:r["checks"].update(visual_completeness_pass=False))
tests["N03_missing_j00"]=blocked(lambda c,r,j:j.update(judgment="BLOCKED"))
tests["N04_quality_sha_semantics"]=blocked(lambda c,r,j:r["checks"].update(packet_hashes_reconcilable=False))
tests["N05_consolidated_sha_tampered"]=blocked(lambda c,r,j:c["elements"][2].update(visible_text="Tampered"))
tests["N06_execution_reuse"]=blocked(lambda c,r,j:r.update(j00_execution_id=r["execution_id"]))
tests["N07_identity_reuse"]=blocked(lambda c,r,j:r.update(j00_identity="P0_VISUAL_READER"))
tests["N08_critical_omission"]=blocked(lambda c,r,j:r["counts"].update(critical_omissions=1))
tests["N09_contradiction"]=blocked(lambda c,r,j:r["counts"].update(contradictions=1))
tests["N10_pending_remediation"]=blocked(lambda c,r,j:r["counts"].update(pending_remediations=1))
tests["N11_unresolved_critical_uncertainty"]=blocked(lambda c,r,j:r["counts"].update(unresolved_critical_uncertainties=1))
def flat(c,r,j):
    c["ui_structure"]["visual_containment_tree"]["edges"]=[{"parent":"ROOT","child":"FORM"},{"parent":"ROOT","child":"BTN"}]; r["consolidated_visual_reading_sha256"]=sha256_value(c); j["candidate_sha256"]=r["consolidated_visual_reading_sha256"]
tests["N12_flat_hierarchy"]=blocked(flat)
tests["N13_unsupported_claim"]=blocked(lambda c,r,j:r["counts"].update(unsupported_claims=1))
tests["N14_source_mismatch"]=blocked(lambda c,r,j:c.update(source_sha256="2"*64))
tests["N15_pass_flag_edit"]=blocked(lambda c,r,j:r.update(human_review_ready=False))
tests["N16_blocked_with_ready"]=blocked(lambda c,r,j:r.update(result="BLOCKED_VISUAL_QUALITY"))
tests["N17_max_remediation"]=blocked(lambda c,r,j:r.update(remediation_cycles=4))
tests["N18_model_unregistered"]=blocked(lambda c,r,j:r["checks"].update(model_configuration_registered=False))
tests["N19_stale_calibration"]=blocked(lambda c,r,j:r["checks"].update(calibration_policy_current=False))
tests["N20_judge_candidate_mismatch"]=blocked(lambda c,r,j:j.update(candidate_sha256="3"*64))
c,r,j=good(); built=build(report=r,consolidated=c,judge=j,review_id="REV1",execution_id="EXEC1",raw_ref="packet://raw",consolidated_ref="packet://consolidated",quality_ref="packet://quality",judge_ref="packet://j00",reviewer_role="P0_VISUAL_ADJUDICATOR",expires_at="2026-08-11T16:00:00Z",data_classification="CONFIDENTIAL")
tests["P02_packet_v3_positive"]=built["result"]=="PASS_WITH_EVIDENCE" and built["packet"]["human_review_ready"] is True
r2=copy.deepcopy(r); r2["counts"]["critical_omissions"]=1; r2["human_review_ready"]=False
built2=build(report=r2,consolidated=c,judge=j,review_id="REV1",execution_id="EXEC1",raw_ref="x",consolidated_ref="y",quality_ref="z",judge_ref="j",reviewer_role="P0_VISUAL_ADJUDICATOR",expires_at="2026-08-11T16:00:00Z",data_classification="CONFIDENTIAL")
tests["P03_packet_v3_fail_closed"]=built2["result"]=="BLOCKED"
failed=[k for k,v in tests.items() if not v]
print(json.dumps({"schema_version":"p0-machine-quality-negative-suite/v1","result":"PASS_WITH_EVIDENCE" if not failed else "BLOCKED","tests":tests,"failed":failed},sort_keys=True))
raise SystemExit(0 if not failed else 2)
