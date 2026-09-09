#!/usr/bin/env python3
"""Strict frozen-bundle binding validator for independent Quality receipts.

Closes the gap between a structurally valid generic receipt and the exact review
case/artifact/bundle it is supposed to certify.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
from typing import Any
from jsonschema import Draft202012Validator

SCORE_KEYS = {
    "contract_schema_compliance",
    "evidence_integrity",
    "lf_safety_governance",
    "handoff_readiness",
    "leakage_scope_control",
}
TOP_KEYS = {
    "receipt_version","execution_mode","semantic_status","review_case_id",
    "reviewer_is_producer","producer_context_available","external_paid_model_used",
    "automated_semantic_judge_implemented","review_completed","source_bundle",
    "quality_review","execution_blockers",
}
SOURCE_KEYS = {
    "artifact_ref","artifact_sha_or_digest","upstream_worker_contract_ref",
    "quality_gate_contract_ref","lf_quality_controls_ref","score_rubric_ref",
    "mini_judge_ref","quality_review_schema_ref",
}
QUALITY_KEYS = {
    "review_id","reviewed_artifact","verdict","score_breakdown","evidence_map",
    "blocking_codes","repair_actions","remaining_risks","next_gate","routing",
}


def _load(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


def _bundle_path(root: Path, ref: str) -> Path | None:
    if not isinstance(ref, str) or not ref.startswith("bundle://"):
        return None
    rel = ref[len("bundle://"):]
    if not rel or rel.startswith("/") or ".." in Path(rel).parts:
        return None
    p=(root/rel).resolve()
    try:p.relative_to(root.resolve())
    except ValueError:return None
    return p if p.is_file() else None


def validate(receipt: Any, root: Path) -> list[str]:
    errors=[]
    if not isinstance(receipt,dict): return ["RECEIPT_NOT_OBJECT"]
    if set(receipt)!=TOP_KEYS:
        errors.append("TOP_LEVEL_KEYS_MISMATCH")

    case=_load(root/'review_case.json')
    indep_schema=_load(root/'independent_semantic_review_receipt.schema.json')
    quality_schema=_load(root/'quality_review.schema.json')

    for name,schema,obj in [('INDEPENDENT_SCHEMA',indep_schema,receipt),('QUALITY_SCHEMA',quality_schema,receipt.get('quality_review'))]:
        try:
            Draft202012Validator(schema).validate(obj)
        except Exception as exc:
            errors.append(name+"_INVALID:"+exc.__class__.__name__)

    sys.path.insert(0,str(root/'validators'))
    from validate_independent_semantic_review import validate_receipt
    from validate_routing import validate_routing
    errors.extend("BASE_RECEIPT:"+e for e in validate_receipt(receipt))

    if receipt.get('review_case_id')!=case.get('review_case_id'):
        errors.append('REVIEW_CASE_ID_MISMATCH')
    source=receipt.get('source_bundle')
    expected_source={
        'artifact_ref':case.get('artifact_ref'),
        'artifact_sha_or_digest':case.get('artifact_canonical_sha256'),
        'upstream_worker_contract_ref':case.get('upstream_worker_contract_ref'),
        'quality_gate_contract_ref':'bundle://quality_gate_contract.md',
        'lf_quality_controls_ref':'bundle://lf_quality_controls.md',
        'score_rubric_ref':'bundle://quality_pack_score_rubric.md',
        'mini_judge_ref':'bundle://quality_pack_mini_judge.md',
        'quality_review_schema_ref':'bundle://quality_review.schema.json',
    }
    if not isinstance(source,dict) or set(source)!=SOURCE_KEYS:
        errors.append('SOURCE_BUNDLE_KEYS_MISMATCH')
    elif source!=expected_source:
        for k,v in expected_source.items():
            if source.get(k)!=v:errors.append('SOURCE_BUNDLE_BINDING_MISMATCH:'+k)

    review=receipt.get('quality_review')
    if not isinstance(review,dict): return sorted(set(errors+['QUALITY_REVIEW_NOT_OBJECT']))
    if set(review)!=QUALITY_KEYS: errors.append('QUALITY_REVIEW_KEYS_MISMATCH')
    if not isinstance(review.get('review_id'),str) or not review['review_id'].startswith(case['review_case_id']+'-'):
        errors.append('REVIEW_ID_NOT_CASE_BOUND')
    expected_reviewed=f"{case['artifact_ref']}#sha256={case['artifact_canonical_sha256']}"
    if review.get('reviewed_artifact')!=expected_reviewed:
        errors.append('REVIEWED_ARTIFACT_BINDING_MISMATCH')
    errors.extend('ROUTING:'+e for e in validate_routing(review.get('verdict'),review.get('routing')))

    evidence=review.get('evidence_map')
    covered=set()
    if not isinstance(evidence,list) or not evidence:
        errors.append('EVIDENCE_MAP_EMPTY')
    else:
        for i,item in enumerate(evidence):
            if not isinstance(item,dict) or set(item)!={'criterion','refs','observed'}:
                errors.append(f'EVIDENCE_ITEM_SHAPE_INVALID:{i}'); continue
            criterion=item.get('criterion')
            if criterion not in SCORE_KEYS: errors.append(f'EVIDENCE_CRITERION_INVALID:{i}')
            else: covered.add(criterion)
            refs=item.get('refs')
            if not isinstance(refs,list) or not refs: errors.append(f'EVIDENCE_REFS_EMPTY:{i}')
            else:
                for ref in refs:
                    if _bundle_path(root,ref) is None: errors.append(f'EVIDENCE_REF_UNRESOLVED:{i}:{ref}')
            if not isinstance(item.get('observed'),str) or not item['observed'].strip():
                errors.append(f'EVIDENCE_OBSERVED_EMPTY:{i}')
    if receipt.get('review_completed') is True and covered!=SCORE_KEYS:
        errors.append('EVIDENCE_CRITERIA_COVERAGE_INCOMPLETE')

    if isinstance(source,dict):
        for key,value in source.items():
            if key=='artifact_sha_or_digest': continue
            if _bundle_path(root,value) is None: errors.append('SOURCE_REF_UNRESOLVED:'+key)

    return sorted(set(errors))


def main()->int:
    ap=argparse.ArgumentParser();ap.add_argument('receipt',type=Path);ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a=ap.parse_args()
    receipt=_load(a.receipt);errors=validate(receipt,a.root.resolve())
    print(json.dumps({'valid':not errors,'errors':errors},ensure_ascii=False,indent=2))
    return 0 if not errors else 1

if __name__=='__main__':raise SystemExit(main())
