#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json
from typing import Any

def derive_human_review_ready(*,clean_pass_count:int,coverage_percent:float,counts:dict,regression_suite:str,adversarial_suite:str,source_sha_binding:str,artifact_hash_chain:str)->bool:
    return bool(clean_pass_count>=2 and coverage_percent==100.0 and counts.get('critical',0)==0 and counts.get('high',0)==0 and counts.get('unresolved_medium',0)==0 and counts.get('suspicious_confirmed',0)==0 and counts.get('contradictions',0)==0 and counts.get('unsupported_claims',0)==0 and counts.get('critical_omissions',0)==0 and regression_suite=='PASS' and adversarial_suite=='PASS' and source_sha_binding=='PASS' and artifact_hash_chain=='PASS')

def convergence_receipt(*,source_sha256:str,code_head_sha:str,configuration_id:str,configuration_sha256:str,clean_passes:list[dict],coverage_percent:float,counts:dict,regression_suite:str,adversarial_suite:str,source_sha_binding:str,artifact_hash_chain:str)->dict:
    ready=derive_human_review_ready(clean_pass_count=len(clean_passes),coverage_percent=coverage_percent,counts=counts,regression_suite=regression_suite,adversarial_suite=adversarial_suite,source_sha_binding=source_sha_binding,artifact_hash_chain=artifact_hash_chain)
    return {'schema_version':'p0-convergence-receipt-v4/v1','source_sha256':source_sha256,'code_head_sha':code_head_sha,'configuration_id':configuration_id,'configuration_sha256':configuration_sha256,'clean_passes':clean_passes,'grader_coverage_percent':coverage_percent,'critical':counts.get('critical',0),'high':counts.get('high',0),'unresolved_medium':counts.get('unresolved_medium',0),'suspicious_confirmed':counts.get('suspicious_confirmed',0),'contradictions':counts.get('contradictions',0),'unsupported_claims':counts.get('unsupported_claims',0),'critical_omissions':counts.get('critical_omissions',0),'regression_suite':regression_suite,'adversarial_suite':adversarial_suite,'source_sha_binding':source_sha_binding,'artifact_hash_chain':artifact_hash_chain,'human_review_ready':ready,'result':'PASS_P0_V4_CLOSED_LOOP' if ready else 'BLOCKED_CONVERGENCE'}

def convergence_receipt_binding(receipt:dict)->dict:
    """Publish the exact serialization contract and digest without self-hashing the receipt."""
    data=json.dumps(receipt,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')
    digest=hashlib.sha256(data).hexdigest()
    return {'schema_version':'p0-convergence-receipt-binding-v4/v1','serialization':'JSON_SORT_KEYS_COMPACT_UTF8_V1','canonical_sha256':digest,'canonical_bytes_sha256':digest,'canonical_bytes_length':len(data)}
