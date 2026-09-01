#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path
from typing import Any

ROOT=Path(__file__).resolve().parents[2]
RUNTIME=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime'
sys.path.insert(0,str(RUNTIME))
from profile_runtime_runner import build_runtime_request
from validate_profile_execution import canonical_json_sha256, sha256_text
from attach_learning_authority_to_profile_manifest_v1 import attach_learning_authority
from learning_context_to_profile_authority_v1 import build_profile_authority


def _profile_source_manifest_sha(profile_sources: list[dict[str,str]]) -> str:
    normalized=sorted(profile_sources,key=lambda x:x['ref'])
    manifest=[{'ref':x['ref'],'content_sha256':sha256_text(x['content'])} for x in normalized]
    return canonical_json_sha256(manifest)


def build_precanary_request(*, execution_id:str, profile_code:str, profile_slug:str,
                             profile_sources:list[dict[str,str]], input_literal:str,
                             base_obligation_manifest:dict[str,Any], learning_envelope:dict[str,Any],
                             lf_adapter_sources:list[dict[str,Any]]|None=None) -> dict[str,Any]:
    if learning_envelope.get('consumer_id')!=profile_code:
        raise ValueError('LEARNING_CONSUMER_PROFILE_MISMATCH')
    expected_profile_sha=_profile_source_manifest_sha(profile_sources)
    if base_obligation_manifest.get('profile_source_sha256')!=expected_profile_sha:
        raise ValueError('BASE_MANIFEST_PROFILE_SOURCE_SHA_MISMATCH')
    expected_input_sha=sha256_text(input_literal)
    if base_obligation_manifest.get('input_sha256')!=expected_input_sha:
        raise ValueError('BASE_MANIFEST_INPUT_SHA_MISMATCH')
    if base_obligation_manifest.get('execution_id')!=execution_id or base_obligation_manifest.get('profile_code')!=profile_code:
        raise ValueError('BASE_MANIFEST_EXECUTION_SCOPE_MISMATCH')
    bridge=build_profile_authority(learning_envelope)
    merged=attach_learning_authority(base_obligation_manifest,bridge)
    request=build_runtime_request(
        execution_id=execution_id, profile_code=profile_code, profile_slug=profile_slug,
        profile_sources=profile_sources,input_literal=input_literal,
        obligation_manifest=merged,lf_adapter_sources=lf_adapter_sources,
    )
    return {
      'request':request,
      'obligation_manifest':merged,
      'learning_envelope_sha256':bridge['envelope_sha256'],
      'runtime_execution_performed':False,
      'status':'PRECANNARY_REQUEST_READY_READ_ONLY'
    }
