#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('build_decomposer_context_pack_v3.py');s=importlib.util.spec_from_file_location('b',p);b=importlib.util.module_from_spec(s);s.loader.exec_module(b)
A='a'*64;B='b'*64
base={'schema':'lf-structural-context-resolver/v3','counts':{'DYNAMIC_DATA':10,'TABLE_HEADER':2},'geometry':{'anchors':{'filter':3,'table_header':2},'header_columns':{'estado':900,'acciones':1100}},'canonical_visibility':[{'field':'Aprobado por','status':'NOT_CURRENTLY_VISIBLE','material_omission':False}],'residual':[{'id':1,'bbox':[1,2,3,4],'role':'TABLE_HEADER','conf':55}]}
out=b.build(base,A,B)
assert out['source_image_sha256']==A and out['context_sha256']==B
assert out['dynamic_data_policy']=='DO_NOT_CANONICAL_RECONCILE'
assert out['canonical_visibility'][0]['material_omission'] is False
assert out['profile_contract_valid']=='NOT_EVALUATED' and out['semantic_utility']=='NOT_EVALUATED'
assert out['resolved_visible_observations']==[]
assert len(out['pack_sha256'])==64
trace={**base,'observations':[{'id':'s1','text':'Rechazaco','effective_text':'Rechazado','effective_text_source':'TARGETED_REREAD','role':'STATE_BADGE','x':10,'y':20,'w':30,'h':12,'reread_provenance':{'psm':6}}]}
t=b.build(trace,A,B)
assert t['resolved_visible_observations'][0]['original_text']=='Rechazaco'
assert t['resolved_visible_observations'][0]['effective_text']=='Rechazado'
assert t['resolved_visible_observations'][0]['bbox']==[10.0,20.0,30.0,12.0]
assert t['data_lineage_policy']=='ORIGINAL_EVIDENCE_IMMUTABLE_EFFECTIVE_TEXT_OVERLAY'
try:b.build({**trace,'observations':[{'id':'d1','text':'Cliente A','effective_text':'Cliente B','effective_text_source':'TARGETED_REREAD','role':'DYNAMIC_DATA','x':1,'y':1,'w':10,'h':10}]},A,B);raise AssertionError('dynamic data overlay accepted')
except ValueError as e: assert str(e)=='overlay_role_not_allowed'
try:b.build({**trace,'observations':[{'id':'s1','text':'Rechazaco','effective_text':'Rechazado','effective_text_source':'CANONICAL_CONTEXT','role':'STATE_BADGE','x':1,'y':1,'w':10,'h':10}]},A,B);raise AssertionError('canonical text source accepted')
except ValueError as e: assert str(e)=='overlay_source_invalid'
try:b.build({**base,'residual':base['residual']*36},A,B);raise AssertionError('residual budget bypass')
except ValueError:pass
try:b.build(base,'bad',B);raise AssertionError('bad sha accepted')
except ValueError:pass
print('DECOMPOSER_CONTEXT_PACK_V3_TESTS_PASS 14/14')
