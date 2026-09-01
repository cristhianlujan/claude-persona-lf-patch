#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
RUNTIME=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime'
sys.path.insert(0,str(RUNTIME))
from semantic_obligation_manifest import validate_obligation_manifest, obligation_manifest_sha256
from learning_context_to_profile_authority_v1 import build_profile_authority
from learning_consumer_request_envelope_v1 import build_envelope


def sha_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()

def context():
    return {
      'schema':'LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V2','mode':'READ_ONLY','selector':'DETERMINISTIC_EXACT_ID',
      'llm_calls':0,'round_trips':0,'tool_calls':0,'consumer_id':'PERFIL-PRODUCT-DIRECTOR-LF','capability_id':'NEGOCIACION_DEUDA',
      'max_context_bytes':6000,'context_bytes':700,'selected_count':2,
      'selected':[
        {'kb_id':'kb-1','summary':'grounded one','evidence_ref':'public.lf_knowledge_base/kb-1'},
        {'kb_id':'kb-2','summary':'grounded two','evidence_ref':'public.lf_knowledge_base/kb-2'}
      ],'fallback':None
    }

def main() -> int:
    env=build_envelope(task_intent='definir alcance',explicit_constraints=['no inventar'],context_pack=context(),binding_id='BIND-LF-PD-NEGOCIACION-DEUDA-v2')
    bridge=build_profile_authority(env)
    assert bridge['authority_source']['authority_type']=='UPSTREAM_CONSTRAINTS'
    assert bridge['writes_allowed'] is False and bridge['profile_source_mutation_required'] is False
    assert len(bridge['obligations'])==3
    assert len(bridge['authority_source']['required_obligation_ids'])==3

    profile_sha=sha_text('profile-source')
    input_sha=sha_text('literal-input')
    manifest={
      'schema':'PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1',
      'execution_id':'learning-authority-fixture-1','profile_code':'PERFIL-PRODUCT-DIRECTOR-LF',
      'profile_source_sha256':profile_sha,'input_sha256':input_sha,
      'authority_sources':[
        {'authority_id':'PROFILE','authority_type':'PROFILE_CONTRACT','source_ref':'profiles/product_director_lf/SKILL.md','source_sha256':profile_sha,'required_obligation_ids':[]},
        {'authority_id':'INPUT','authority_type':'EXECUTION_INPUT','source_ref':'fixture:literal-input','source_sha256':input_sha,'required_obligation_ids':[]},
        bridge['authority_source']
      ],
      'obligations':bridge['obligations']
    }
    normalized=validate_obligation_manifest(manifest,expected_execution_id='learning-authority-fixture-1',expected_profile_code='PERFIL-PRODUCT-DIRECTOR-LF',expected_profile_source_sha256=profile_sha,expected_input_sha256=input_sha)
    digest=obligation_manifest_sha256(normalized)
    assert len(digest)==64
    assert {x['authority_type'] for x in normalized['authority_sources']}=={'PROFILE_CONTRACT','EXECUTION_INPUT','UPSTREAM_CONSTRAINTS'}
    print('LEARNING_CONTEXT_TO_PROFILE_AUTHORITY=PASS obligations=3 authority_type=UPSTREAM_CONSTRAINTS manifest_contract=PASS profile_mutation=0 writes=0')
    return 0

if __name__=='__main__': raise SystemExit(main())
