#!/usr/bin/env python3
"""Fail-closed P0 machine visual-quality gate.

This validator derives HUMAN_REVIEW_READY from evidence-bound hard gates. It never
trusts a stored PASS/ready flag as authority.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any

SHA256_KEYS = ("source_sha256","raw_visual_output_sha256","consolidated_visual_reading_sha256")
REQUIRED_ZERO = ("critical_omissions","contradictions","unsupported_claims","pending_remediations","unresolved_critical_uncertainties")
REQUIRED_CHECKS = (
    "evidence_integrity_pass","visual_structure_pass","visual_semantic_pass",
    "visual_completeness_pass","source_admission_binding_pass","j00_independence_pass",
    "security_pass","privacy_pass","model_configuration_registered","calibration_policy_current",
    "packet_hashes_reconcilable"
)
LEGACY_BAD_SHA="c0acd3f52388447958b9f60c839f7f4e289488110654784b9d9f94cfccb8b6ff"

def canonical_bytes(value: Any)->bytes:
    return json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()

def sha256_value(value: Any)->str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()

def derive(report: dict[str,Any], consolidated: dict[str,Any]|None=None, judge: dict[str,Any]|None=None)->dict[str,Any]:
    reasons=[]
    counts=report.get("counts") if isinstance(report.get("counts"),dict) else {}
    checks=report.get("checks") if isinstance(report.get("checks"),dict) else {}
    if report.get("schema_version")!="p0-machine-visual-quality-report/v1":
        reasons.append("MACHINE_QUALITY_SCHEMA_VERSION_INVALID")
    for key in SHA256_KEYS:
        value=report.get(key)
        if not isinstance(value,str) or len(value)!=64 or any(c not in "0123456789abcdef" for c in value):
            reasons.append(f"{key.upper()}_INVALID")
    if report.get("raw_visual_output_sha256")==LEGACY_BAD_SHA:
        reasons += ["OCR_ONLY_OUTPUT_NOT_HUMAN_READY","SEMANTIC_UI_COVERAGE_MISSING","VISUAL_STRUCTURE_DEGENERATE","MACHINE_AUDIT_NOT_PRESENT"]
    if report.get("execution_id")==report.get("j00_execution_id"):
        reasons.append("J00_EXECUTION_REUSE")
    if report.get("j00_identity") in {None,"","P0_VISUAL_READER","reader"}:
        reasons.append("J00_IDENTITY_NOT_INDEPENDENT")
    if report.get("remediation_cycles",0)>report.get("max_remediation_cycles",0):
        reasons.append("REMEDIATION_BUDGET_EXCEEDED")
    for key in REQUIRED_ZERO:
        if counts.get(key)!=0:
            reasons.append(f"{key.upper()}_NONZERO")
    for key in REQUIRED_CHECKS:
        if checks.get(key) is not True:
            reasons.append(f"{key.upper()}_FAILED")
    if report.get("result")!="PASS_VISUAL_QUALITY":
        reasons.append("MACHINE_QUALITY_RESULT_NOT_PASS")
    if consolidated is not None:
        observed=sha256_value(consolidated)
        if observed!=report.get("consolidated_visual_reading_sha256"):
            reasons.append("CONSOLIDATED_SHA_MISMATCH")
        if consolidated.get("source_sha256")!=report.get("source_sha256"):
            reasons.append("SOURCE_CONSOLIDATED_MISMATCH")
        elements=consolidated.get("elements")
        if not isinstance(elements,list) or not elements:
            reasons.append("CONSOLIDATED_ELEMENTS_EMPTY")
        else:
            if all(isinstance(x,dict) and x.get("element_type") in {"TEXT","UNKNOWN_VISUAL_ELEMENT"} for x in elements):
                reasons.append("SEMANTIC_UI_COVERAGE_MISSING")
            tree=consolidated.get("ui_structure",{}).get("visual_containment_tree",{})
            edges=tree.get("edges",[]) if isinstance(tree,dict) else []
            parents={e.get("parent") for e in edges if isinstance(e,dict)}
            if len(parents)<=1 and len(elements)>1:
                reasons.append("VISUAL_STRUCTURE_DEGENERATE")
            unresolved=sum(1 for x in elements if isinstance(x,dict) and x.get("machine_resolution_status")=="REMEDIATION_REQUIRED")
            if unresolved:
                reasons.append("ELEMENT_REMEDIATION_PENDING")
    if judge is not None:
        if judge.get("execution_id")!=report.get("j00_execution_id"):
            reasons.append("J00_EXECUTION_MISMATCH")
        if judge.get("identity")!=report.get("j00_identity"):
            reasons.append("J00_IDENTITY_MISMATCH")
        if judge.get("judgment")!="PASS":
            reasons.append("J00_JUDGMENT_NOT_PASS")
        if judge.get("source_sha256")!=report.get("source_sha256"):
            reasons.append("J00_SOURCE_SHA_MISMATCH")
        if judge.get("candidate_sha256")!=report.get("consolidated_visual_reading_sha256"):
            reasons.append("J00_CANDIDATE_SHA_MISMATCH")
    derived_ready=not reasons
    if bool(report.get("human_review_ready")) != derived_ready:
        reasons.append("HUMAN_REVIEW_READY_FLAG_NOT_DERIVED")
        derived_ready=False
    return {"result":"PASS_VISUAL_QUALITY" if derived_ready else "BLOCKED_VISUAL_QUALITY",
            "human_review_ready":derived_ready,
            "blocking_assertions":sorted(set(reasons))}

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--report",type=Path,required=True)
    ap.add_argument("--consolidated",type=Path)
    ap.add_argument("--judge",type=Path)
    args=ap.parse_args()
    load=lambda p: json.loads(p.read_text())
    result=derive(load(args.report),load(args.consolidated) if args.consolidated else None,load(args.judge) if args.judge else None)
    print(json.dumps(result,sort_keys=True))
    return 0 if result["human_review_ready"] else 2

if __name__=="__main__": raise SystemExit(main())
