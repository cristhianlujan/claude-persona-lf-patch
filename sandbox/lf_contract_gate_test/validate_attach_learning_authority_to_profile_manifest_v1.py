#!/usr/bin/env python3
from __future__ import annotations
import hashlib,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
RUNTIME=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime'
sys.path.insert(0,str(RUNTIME))
from semantic_obligation_manifest import validate_obligation_manifest, obligation_manifest_sha256
from attach_learning_authority_to_profile_manifest_v1 import attach_learning_authority
from learning_context_to_profile_authority_v1 import build_profile_authority
from learning_consumer_request_envelope_v1 import build_envelope


def h(text:str)->str: return hashlib.sha256(text.encode()).hexdigest()

def must_fail(fn):
    try: fn()
    except (ValueError,Exception) as exc:
        if type(exc).__name__ in {'AssertionError'}: raise
        return
    raise SystemExit('FAIL expected rejection')

def main()->int:
    profile_sha=h('profile'); input_sha=h('input')
    base={
      'schema':'PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1','execution_id':'exec-1','profile_code':'PERFIL-PRODUCT-DIRECTOR-LF',
      'profile_source_sha256':profile_sha,'input_sha256':input_sha,
      'authority_sources':[
        {'authority_id':'PROFILE','authority_type':'PROFILE_CONTRACT','source_ref':'profiles/product_director_lf/SKILL.md','source_sha256':profile_sha,'required_obligation_ids':['PROFILE.RETAIN']},
        {'authority_id':'INPUT','authority_type':'EXECUTION_INPUT','source_ref':'literal-input','source_sha256':input_sha,'required_obligation_ids':['INPUT.RETAIN']}
      ],
      'obligations':[
        {'obligation_id':'PROFILE.RETAIN','rule':'Preserve profile contract.','check_type':'SEMANTIC_RELATION','evidence_pointer':'$','authority_ids':['PROFILE'],'question':'Does output preserve profile contract?'},
        {'obligation_id':'INPUT.RETAIN','rule':'Preserve explicit input.','check_type':'SEMANTIC_RELATION','evidence_pointer':'$','authority_ids':['INPUT'],'question':'Does output preserve explicit input?'}
      ]
    }
    validate_obligation_manifest(base)
    context={'schema':'LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V2','mode':'READ_ONLY','selector':'DETERMINISTIC_EXACT_ID','llm_calls':0,'round_trips':0,'tool_calls':0,'consumer_id':'PERFIL-PRODUCT-DIRECTOR-LF','capability_id':'NEGOCIACION_DEUDA','max_context_bytes':6000,'context_bytes':500,'selected_count':1,'selected':[{'kb_id':'kb-1','summary':'grounded','evidence_ref':'public.lf_knowledge_base/kb-1'}],'fallback':None}
    envelope=build_envelope(task_intent='product scope',explicit_constraints=['no inventar'],context_pack=context,binding_id='BIND-LF-PD-NEGOCIACION-DEUDA-v2')
    bridge=build_profile_authority(envelope)
    merged=attach_learning_authority(base,bridge)
    ids={x['obligation_id'] for x in merged['obligations']}
    assert {'PROFILE.RETAIN','INPUT.RETAIN','LEARNING.CONTEXT.AUTHORITY_BOUNDARY','LEARNING.CONTEXT.EVIDENCE.01'}<=ids
    types={x['authority_type'] for x in merged['authority_sources']}
    assert {'PROFILE_CONTRACT','EXECUTION_INPUT','UPSTREAM_CONSTRAINTS'}<=types
    assert len(merged['obligations'])==4
    assert len(obligation_manifest_sha256(merged))==64
    must_fail(lambda: attach_learning_authority(merged,bridge))
    print('ATTACH_LEARNING_AUTHORITY_TO_PROFILE_MANIFEST=PASS original_obligations=2 learning_obligations=2 total=4 no_overwrite=1 duplicate_blocked=1')
    return 0
if __name__=='__main__': raise SystemExit(main())
