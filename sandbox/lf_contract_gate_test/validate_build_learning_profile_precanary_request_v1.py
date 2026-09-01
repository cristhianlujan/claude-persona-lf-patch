#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
RUNTIME=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime'
sys.path.insert(0,str(RUNTIME))
from semantic_obligation_manifest import obligation_manifest_sha256
from validate_profile_execution import canonical_json_sha256,sha256_text
from build_learning_profile_precanary_request_v1 import build_precanary_request
from learning_consumer_request_envelope_v1 import build_envelope


def source_manifest_sha(sources):
    manifest=[{'ref':x['ref'],'content_sha256':sha256_text(x['content'])} for x in sorted(sources,key=lambda x:x['ref'])]
    return canonical_json_sha256(manifest)

def main()->int:
    sources=[{'ref':'profiles/product_director_lf/SKILL.md','content':'canonical product director profile fixture'}]
    input_literal='Define product scope without inventing eligibility.'
    profile_sha=source_manifest_sha(sources); input_sha=sha256_text(input_literal)
    base={
      'schema':'PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1','execution_id':'precanary-learning-1','profile_code':'PERFIL-PRODUCT-DIRECTOR-LF',
      'profile_source_sha256':profile_sha,'input_sha256':input_sha,
      'authority_sources':[
        {'authority_id':'PROFILE','authority_type':'PROFILE_CONTRACT','source_ref':sources[0]['ref'],'source_sha256':profile_sha,'required_obligation_ids':['PROFILE.RETAIN']},
        {'authority_id':'INPUT','authority_type':'EXECUTION_INPUT','source_ref':'fixture:input','source_sha256':input_sha,'required_obligation_ids':['INPUT.RETAIN']}
      ],
      'obligations':[
        {'obligation_id':'PROFILE.RETAIN','rule':'Preserve product director authority.','check_type':'SEMANTIC_RELATION','evidence_pointer':'$','authority_ids':['PROFILE'],'question':'Does output preserve product director authority?'},
        {'obligation_id':'INPUT.RETAIN','rule':'Preserve explicit request constraints.','check_type':'SEMANTIC_RELATION','evidence_pointer':'$','authority_ids':['INPUT'],'question':'Does output preserve explicit request constraints?'}
      ]
    }
    ctx={'schema':'LF_LEARNING_READ_ONLY_CONTEXT_SELECTION_V2','mode':'READ_ONLY','selector':'DETERMINISTIC_EXACT_ID','llm_calls':0,'round_trips':0,'tool_calls':0,'consumer_id':'PERFIL-PRODUCT-DIRECTOR-LF','capability_id':'NEGOCIACION_DEUDA','max_context_bytes':6000,'context_bytes':500,'selected_count':1,'selected':[{'kb_id':'kb-1','summary':'grounded','evidence_ref':'public.lf_knowledge_base/kb-1'}],'fallback':None}
    env=build_envelope(task_intent='product scope',explicit_constraints=['no inventar elegibilidad'],context_pack=ctx,binding_id='BIND-LF-PD-NEGOCIACION-DEUDA-v2')
    built=build_precanary_request(execution_id='precanary-learning-1',profile_code='PERFIL-PRODUCT-DIRECTOR-LF',profile_slug='product_director_lf',profile_sources=sources,input_literal=input_literal,base_obligation_manifest=base,learning_envelope=env)
    request=built['request']; manifest=built['obligation_manifest']
    assert built['runtime_execution_performed'] is False
    assert request['obligation_manifest_sha256']==obligation_manifest_sha256(manifest)
    assert request['profile_source_sha256']==profile_sha and request['input_sha256']==input_sha
    assert len(request['request_sha256'])==64
    assert any(x['authority_type']=='UPSTREAM_CONSTRAINTS' for x in manifest['authority_sources'])
    assert len(manifest['obligations'])==4
    print('LEARNING_PROFILE_PRECANARY_REQUEST=PASS request_sha_bound=1 manifest_sha_bound=1 upstream_constraints=1 runtime_execution=0 profile_mutation=0')
    return 0
if __name__=='__main__': raise SystemExit(main())
