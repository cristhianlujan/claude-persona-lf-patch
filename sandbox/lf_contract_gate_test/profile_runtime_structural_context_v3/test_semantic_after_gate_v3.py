#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('semantic_after_gate_v3.py');s=importlib.util.spec_from_file_location('sag',p);g=importlib.util.module_from_spec(s);s.loader.exec_module(g)

def good():
 return {'artifact_sha256':g.ARTIFACT_SHA,'critical_regressions_count':0,'results':[{'profile_code':c,'transport_status':'SUCCEEDED','contract_valid':True,'semantic_utility_valid':True,'output_sha256':('a' if i==0 else 'b' if i==1 else 'c')*64,'runtime_observed_ms':1000+i} for i,c in enumerate(sorted(g.EXPECTED_PROFILES))]}

assert g.evaluate(good()).pass_after
x=good(); x['artifact_sha256']='0'*64; assert not g.evaluate(x).pass_after and 'ARTIFACT_SHA_MISMATCH' in g.evaluate(x).reasons
x=good(); x['results']=x['results'][:2]; assert not g.evaluate(x).pass_after and 'RESULT_COUNT_NOT_3' in g.evaluate(x).reasons
x=good(); x['results'][0]['transport_status']='SUCCEEDED'; x['results'][0]['contract_valid']=False; assert not g.evaluate(x).pass_after
x=good(); x['results'][1]['semantic_utility_valid']=False; assert not g.evaluate(x).pass_after
x=good(); x['results'][2]['output_sha256']=''; assert not g.evaluate(x).pass_after
x=good(); x['results'][2]['runtime_observed_ms']=0; assert not g.evaluate(x).pass_after
x=good(); x['critical_regressions_count']=1; assert not g.evaluate(x).pass_after
print('SEMANTIC_AFTER_GATE_V3_TESTS_PASS 8/8')
