#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,re
from typing import Any
HEX64=re.compile(r'^[0-9a-f]{64}$')
PROOF_SCHEMA='p0-v4-gate-proof/v1'
PASS_RESULT='PASS_WITH_EVIDENCE'

def _canonical(value:Any)->bytes:return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')
def _proof_digest(proof:dict)->str:
    body={k:v for k,v in proof.items() if k!='evidence_sha256'}
    return hashlib.sha256(_canonical(body)).hexdigest()
def make_gate_proof(*,gate:str,source_sha256:str,code_head_sha:str,configuration_sha256:str,details:dict|None=None,passed:bool=True,exit_code:int=0)->dict:
    proof={'schema_version':PROOF_SCHEMA,'gate':gate,'executed':True,'result':PASS_RESULT if passed else 'BLOCKED','exit_code':exit_code,'source_sha256':source_sha256,'code_head_sha':code_head_sha,'configuration_sha256':configuration_sha256,'details':details or {}}
    proof['evidence_sha256']=_proof_digest(proof)
    return proof
def validate_gate_proof(proof:Any,*,gate:str,source_sha256:str,code_head_sha:str,configuration_sha256:str)->bool:
    if not isinstance(proof,dict):return False
    if proof.get('schema_version')!=PROOF_SCHEMA or proof.get('gate')!=gate:return False
    if proof.get('executed') is not True or proof.get('result')!=PASS_RESULT or proof.get('exit_code')!=0:return False
    if proof.get('source_sha256')!=source_sha256 or proof.get('code_head_sha')!=code_head_sha or proof.get('configuration_sha256')!=configuration_sha256:return False
    digest=proof.get('evidence_sha256')
    return bool(isinstance(digest,str) and HEX64.fullmatch(digest) and digest==_proof_digest(proof))
def derive_human_review_ready(*,clean_pass_count:int,coverage_percent:float,counts:dict,regression_proof:dict|None,adversarial_proof:dict|None,source_binding_proof:dict|None,artifact_hash_proof:dict|None,source_sha256:str,code_head_sha:str,configuration_sha256:str)->bool:
    proofs_ok=(
        validate_gate_proof(regression_proof,gate='regression_suite',source_sha256=source_sha256,code_head_sha=code_head_sha,configuration_sha256=configuration_sha256)
        and validate_gate_proof(adversarial_proof,gate='adversarial_suite',source_sha256=source_sha256,code_head_sha=code_head_sha,configuration_sha256=configuration_sha256)
        and validate_gate_proof(source_binding_proof,gate='source_sha_binding',source_sha256=source_sha256,code_head_sha=code_head_sha,configuration_sha256=configuration_sha256)
        and validate_gate_proof(artifact_hash_proof,gate='artifact_hash_chain',source_sha256=source_sha256,code_head_sha=code_head_sha,configuration_sha256=configuration_sha256)
    )
    return bool(clean_pass_count>=2 and coverage_percent==100.0 and counts.get('critical',0)==0 and counts.get('high',0)==0 and counts.get('unresolved_medium',0)==0 and counts.get('suspicious_confirmed',0)==0 and counts.get('contradictions',0)==0 and counts.get('unsupported_claims',0)==0 and counts.get('critical_omissions',0)==0 and proofs_ok)
def convergence_receipt(*,source_sha256:str,code_head_sha:str,configuration_id:str,configuration_sha256:str,clean_passes:list[dict],coverage_percent:float,counts:dict,regression_proof:dict|None,adversarial_proof:dict|None,source_binding_proof:dict|None,artifact_hash_proof:dict|None)->dict:
    ready=derive_human_review_ready(clean_pass_count=len(clean_passes),coverage_percent=coverage_percent,counts=counts,regression_proof=regression_proof,adversarial_proof=adversarial_proof,source_binding_proof=source_binding_proof,artifact_hash_proof=artifact_hash_proof,source_sha256=source_sha256,code_head_sha=code_head_sha,configuration_sha256=configuration_sha256)
    return {'schema_version':'p0-convergence-receipt-v4/v2','source_sha256':source_sha256,'code_head_sha':code_head_sha,'configuration_id':configuration_id,'configuration_sha256':configuration_sha256,'clean_passes':clean_passes,'grader_coverage_percent':coverage_percent,'critical':counts.get('critical',0),'high':counts.get('high',0),'unresolved_medium':counts.get('unresolved_medium',0),'suspicious_confirmed':counts.get('suspicious_confirmed',0),'contradictions':counts.get('contradictions',0),'unsupported_claims':counts.get('unsupported_claims',0),'critical_omissions':counts.get('critical_omissions',0),'gate_proofs':{'regression_suite':regression_proof,'adversarial_suite':adversarial_proof,'source_sha_binding':source_binding_proof,'artifact_hash_chain':artifact_hash_proof},'human_review_ready':ready,'result':'PASS_P0_V4_CLOSED_LOOP' if ready else 'BLOCKED_CONVERGENCE'}
def convergence_receipt_binding(receipt:dict)->dict:
    """External binding: hashes the logical receipt; never self-hashes a field inside it."""
    canonical_bytes=_canonical(receipt);canonical_digest=hashlib.sha256(canonical_bytes).hexdigest()
    return {'schema_version':'p0-convergence-receipt-binding-v4/v2','canonicalization':'JSON_SORT_KEYS_COMPACT_UTF8_V1','logical_receipt_canonical_sha256':canonical_digest,'logical_receipt_canonical_bytes_sha256':canonical_digest,'logical_receipt_canonical_bytes_length':len(canonical_bytes),'digest_semantics':{'logical_receipt_canonical_sha256':'SHA-256 of the convergence receipt after the documented canonical JSON serialization','persisted_object_bytes_sha256':'Must be taken from the append-only persistence envelope/readback and may differ if storage serialization differs'},'detector_diversity':{'ocr_engine_families':['TESSERACT'],'object_detector_families':['OPENCV_CANNY'],'second_ocr_engine_evaluation':'DEFERRED_NOT_IN_RUNTIME','reason':'No second OCR model family has a governed pinned model/weights artifact and CI reproducibility evidence in this repository. Human review packet must retain this limitation; correlated Tesseract errors remain possible.'}}
