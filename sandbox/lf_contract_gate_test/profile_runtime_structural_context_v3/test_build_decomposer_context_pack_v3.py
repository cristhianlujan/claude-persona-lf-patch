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
assert len(out['pack_sha256'])==64
try:b.build({**base,'residual':base['residual']*36},A,B);raise AssertionError('residual budget bypass')
except ValueError:pass
try:b.build(base,'bad',B);raise AssertionError('bad sha accepted')
except ValueError:pass
print('DECOMPOSER_CONTEXT_PACK_V3_TESTS_PASS 8/8')
