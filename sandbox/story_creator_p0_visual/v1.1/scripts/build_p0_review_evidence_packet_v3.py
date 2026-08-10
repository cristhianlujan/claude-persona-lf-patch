#!/usr/bin/env python3
"""Build human-review packet v3 only from derived machine-quality PASS."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any
from validate_p0_machine_visual_quality import derive, canonical_bytes

def build(*,report:dict[str,Any],consolidated:dict[str,Any],judge:dict[str,Any],review_id:str,execution_id:str,raw_ref:str,consolidated_ref:str,quality_ref:str,judge_ref:str,reviewer_role:str,expires_at:str,data_classification:str)->dict[str,Any]:
    gate=derive(report,consolidated,judge)
    if not gate["human_review_ready"]:
        return {"result":"BLOCKED","blocking_assertions":gate["blocking_assertions"]}
    quality_sha=hashlib.sha256(canonical_bytes(report)).hexdigest()
    counts=report["counts"]
    packet={
      "schema_version":"p0-human-review-packet-v3/v1","review_id":review_id,"execution_id":execution_id,
      "source_refs":consolidated["source_image_refs"],"raw_visual_output_ref":raw_ref,
      "consolidated_visual_reading_ref":consolidated_ref,"machine_quality_report_ref":quality_ref,
      "machine_quality_report_sha256":quality_sha,"j00_judgment_ref":judge_ref,"human_review_ready":True,
      "reviewer_role":reviewer_role,"expires_at":expires_at,"data_classification":data_classification,
      "summary":{"elements_consolidated":counts["consolidated_elements"],"confirmed":counts["confirmed"],"inferred":counts["inferred"],
                 "not_observable":counts["not_observable"],"automatic_remediations":report["remediation_cycles"],
                 "critical_omissions":counts["critical_omissions"],"contradictions":counts["contradictions"],
                 "machine_quality_result":report["result"]},
      "region_rows":[{"element_id":e["element_id"],"element_type":e["element_type"],"visible_text":e.get("visible_text"),
                      "classification":e["classification"],"evidence_refs":e["evidence_refs"],"uncertainty_codes":e["uncertainty_codes"]}
                     for e in consolidated["elements"]]
    }
    return {"result":"PASS_WITH_EVIDENCE","packet":packet,"machine_quality_report_sha256":quality_sha}

def main()->int:
    ap=argparse.ArgumentParser()
    for n in ("report","consolidated","judge"): ap.add_argument("--"+n,type=Path,required=True)
    ap.add_argument("--review-id",required=True); ap.add_argument("--execution-id",required=True)
    ap.add_argument("--raw-ref",required=True); ap.add_argument("--consolidated-ref",required=True); ap.add_argument("--quality-ref",required=True); ap.add_argument("--judge-ref",required=True)
    ap.add_argument("--reviewer-role",required=True); ap.add_argument("--expires-at",required=True); ap.add_argument("--data-classification",required=True)
    args=ap.parse_args(); load=lambda p: json.loads(p.read_text())
    result=build(report=load(args.report),consolidated=load(args.consolidated),judge=load(args.judge),review_id=args.review_id,execution_id=args.execution_id,
                 raw_ref=args.raw_ref,consolidated_ref=args.consolidated_ref,quality_ref=args.quality_ref,judge_ref=args.judge_ref,
                 reviewer_role=args.reviewer_role,expires_at=args.expires_at,data_classification=args.data_classification)
    print(json.dumps(result,sort_keys=True))
    return 0 if result["result"]=="PASS_WITH_EVIDENCE" else 2
if __name__=="__main__": raise SystemExit(main())
