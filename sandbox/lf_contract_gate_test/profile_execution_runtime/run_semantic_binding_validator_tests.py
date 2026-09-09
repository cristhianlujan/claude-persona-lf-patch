#!/usr/bin/env python3
import copy
from semantic_binding_validator import SCHEMA, canonical_sha, validate

source={"schema":"LF_SOURCE_FIDELITY_CONTRACT_V1","contract_sha256":"a"*64,"immutable_entities":[
 {"entity_id":"title","kind":"LABEL","semantic_signature":{"label":"Historial"}},
 {"entity_id":"actions","kind":"ACTIONS","semantic_signature":{"labels":["Ver detalle","Original"]}},
 {"entity_id":"order","kind":"ORDER","semantic_signature":{"ordered_labels":["A","B"]}},
]}
artifact={"composer_payload":{"title":"Historial","actions":["Ver detalle","Original"],"headers":["A","B"]}}
binding={"schema":SCHEMA,"artifact_canonical_sha256":canonical_sha(artifact),"source_fidelity_contract_sha256":"a"*64,"bindings":[
 {"entity_id":"title","artifact_pointer":"/composer_payload/title","signature_key":"label","comparison":"EXACT"},
 {"entity_id":"actions","artifact_pointer":"/composer_payload/actions","signature_key":"labels","comparison":"LIST_EXACT"},
 {"entity_id":"order","artifact_pointer":"/composer_payload/headers","signature_key":"ordered_labels","comparison":"LIST_EXACT"},
]}
binding['binding_sha256']=canonical_sha(binding)

def run(name,s,a,b,expect):
    errors=validate(s,a,b); actual=not errors
    assert actual==expect,(name,errors)
    print('PASS',name,'valid='+str(actual))

run('base',source,artifact,binding,True)
a=copy.deepcopy(artifact);a['composer_payload']['title']='Otro';b=copy.deepcopy(binding);b['artifact_canonical_sha256']=canonical_sha(a);b['binding_sha256']=canonical_sha({k:v for k,v in b.items() if k!='binding_sha256'});run('mutated_label',source,a,b,False)
a=copy.deepcopy(artifact);a['composer_payload']['headers']=['B','A'];b=copy.deepcopy(binding);b['artifact_canonical_sha256']=canonical_sha(a);b['binding_sha256']=canonical_sha({k:v for k,v in b.items() if k!='binding_sha256'});run('reordered',source,a,b,False)
b=copy.deepcopy(binding);b['bindings']=b['bindings'][:-1];b['binding_sha256']=canonical_sha({k:v for k,v in b.items() if k!='binding_sha256'});run('missing_binding',source,artifact,b,False)

source2={"schema":"LF_SOURCE_FIDELITY_CONTRACT_V1","contract_sha256":"b"*64,"immutable_entities":[
 {"entity_id":"title","kind":"LABEL","semantic_signature":{"label":"Historial"}},
]}
artifact2={"composer_payload":{"title":"Historial","state":{"record_count_binding":"LIVE_FILTERED_RESULT_COUNT","page_size_binding":"LIVE_PAGE_SIZE_STATE"}}}
binding2={"schema":SCHEMA,"artifact_canonical_sha256":canonical_sha(artifact2),"source_fidelity_contract_sha256":"b"*64,"bindings":[
 {"entity_id":"title","artifact_pointer":"/composer_payload/title","signature_key":"label","comparison":"EXACT"}],
 "dynamic_bindings":[
  {"binding_id":"record_count","artifact_pointer":"/composer_payload/state/record_count_binding","expected_binding":"LIVE_FILTERED_RESULT_COUNT"},
  {"binding_id":"page_size","artifact_pointer":"/composer_payload/state/page_size_binding","expected_binding":"LIVE_PAGE_SIZE_STATE"}],
 "forbidden_render_literals":[
  {"literal_id":"record_count_literal","artifact_pointer":"/composer_payload/state/record_count","must_be_absent":True},
  {"literal_id":"page_size_literal","artifact_pointer":"/composer_payload/state/page_size","must_be_absent":True}]}
binding2['binding_sha256']=canonical_sha(binding2)
run('dynamic_base',source2,artifact2,binding2,True)
a=copy.deepcopy(artifact2);a['composer_payload']['state']['record_count']=6;b=copy.deepcopy(binding2);b['artifact_canonical_sha256']=canonical_sha(a);b['binding_sha256']=canonical_sha({k:v for k,v in b.items() if k!='binding_sha256'});run('dynamic_literal_record_count',source2,a,b,False)
a=copy.deepcopy(artifact2);a['composer_payload']['state']['record_count_binding']='STATIC_6';b=copy.deepcopy(binding2);b['artifact_canonical_sha256']=canonical_sha(a);b['binding_sha256']=canonical_sha({k:v for k,v in b.items() if k!='binding_sha256'});run('dynamic_wrong_binding',source2,a,b,False)
print('SEMANTIC_BINDING_REGRESSIONS_PASS=7/7')
