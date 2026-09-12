#!/usr/bin/env python3
"""Fail-closed validator for new P0 human-review packets.

Historical packet v2 objects remain readable elsewhere, but cannot be elevated
through this validator because they lack the v3 machine-quality/J00 binding.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any
from validate_p0_machine_visual_quality import derive, canonical_bytes

def sha(v:Any)->str:return hashlib.sha256(canonical_bytes(v)).hexdigest()
def validate(packet:dict[str,Any]|None, report:dict[str,Any]|None, consolidated:dict[str,Any]|None, judge:dict[str,Any]|None)->dict[str,Any]:
    reasons=[]
    if not isinstance(packet,dict): return {"result":"BLOCKED","human_review_ready":False,"blocking_assertions":["HUMAN_PACKET_MISSING"]}
    if packet.get("schema_version")!="p0-human-review-packet-v3/v1": reasons.append("LEGACY_PACKET_NOT_ELIGIBLE_FOR_NEW_HUMAN_GATE")
    if not isinstance(report,dict): reasons.append("P0H_MACHINE_QUALITY_REPORT_MISSING")
    if not isinstance(consolidated,dict): reasons.append("CONSOLIDATED_VISUAL_READING_MISSING")
    if not isinstance(judge,dict): reasons.append("J00_MACHINE_JUDGMENT_MISSING")
    if reasons:return {"result":"BLOCKED","human_review_ready":False,"blocking_assertions":sorted(set(reasons))}
    gate=derive(report,consolidated,judge)
    if not gate["human_review_ready"]: reasons.extend(gate["blocking_assertions"] or ["MACHINE_QUALITY_NOT_READY"])
    if packet.get("machine_quality_report_sha256")!=sha(report): reasons.append("MACHINE_QUALITY_REPORT_SHA_MISMATCH")
    if report.get("consolidated_visual_reading_sha256")!=sha(consolidated): reasons.append("CONSOLIDATED_VISUAL_READING_SHA_MISMATCH")
    if packet.get("human_review_ready") is not True: reasons.append("PACKET_HUMAN_REVIEW_READY_NOT_TRUE")
    if report.get("human_review_ready") is not True: reasons.append("REPORT_HUMAN_REVIEW_READY_NOT_TRUE")
    if packet.get("j00_judgment_ref") in {None,""}: reasons.append("J00_JUDGMENT_REF_MISSING")
    if packet.get("machine_quality_report_ref") in {None,""}: reasons.append("MACHINE_QUALITY_REPORT_REF_MISSING")
    if packet.get("consolidated_visual_reading_ref") in {None,""}: reasons.append("CONSOLIDATED_VISUAL_READING_REF_MISSING")
    if packet.get("raw_visual_output_ref") in {None,""}: reasons.append("RAW_VISUAL_OUTPUT_REF_MISSING")
    if packet.get("source_refs")!=consolidated.get("source_image_refs"): reasons.append("PACKET_SOURCE_REFS_MISMATCH")
    ready=not reasons
    return {"result":"PASS_WITH_EVIDENCE" if ready else "BLOCKED","human_review_ready":ready,"blocking_assertions":sorted(set(reasons))}
def main()->int:
    ap=argparse.ArgumentParser();ap.add_argument('--packet',type=Path,required=True);ap.add_argument('--report',type=Path);ap.add_argument('--consolidated',type=Path);ap.add_argument('--judge',type=Path)
    a=ap.parse_args();load=lambda p:json.loads(p.read_text()) if p else None
    r=validate(load(a.packet),load(a.report),load(a.consolidated),load(a.judge));print(json.dumps(r,sort_keys=True));return 0 if r['human_review_ready'] else 2
if __name__=='__main__':raise SystemExit(main())
