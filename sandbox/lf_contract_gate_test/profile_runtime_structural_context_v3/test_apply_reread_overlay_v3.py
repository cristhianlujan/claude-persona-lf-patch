#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('apply_reread_overlay_v3.py');s=importlib.util.spec_from_file_location('o',p);o=importlib.util.module_from_spec(s);s.loader.exec_module(o)
base={'schema':'lf-structural-context-resolver/v3','observations':[{'id':1,'text':'detate','x':10,'y':20,'w':30,'h':10,'role':'ROW_ACTION'},{'id':2,'text':'Mas','x':50,'y':20,'w':20,'h':10,'role':'FILTER_BAR'}]}
rr={'regions':[{'id':1,'role':'ROW_ACTION','bbox':[10,20,30,10],'decision':{'adopted':True,'source':'TARGETED_REREAD','text':'Ver detalle'}},{'id':2,'role':'FILTER_BAR','bbox':[50,20,20,10],'decision':{'adopted':False,'source':'ORIGINAL_OCR','text':'Mas'}}]}
out=o.apply_overlay(base,rr)
assert out['observations'][0]['text']=='detate' and out['observations'][0]['effective_text']=='Ver detalle'
assert 'effective_text' not in out['observations'][1]
assert out['reread_overlay']['adopted_count']==1 and out['reread_overlay']['original_evidence_mutated'] is False
assert base['observations'][0].get('effective_text') is None
try:o.apply_overlay(base,{'regions':rr['regions']+[rr['regions'][0]]});raise AssertionError
except ValueError as e:assert 'duplicate' in str(e)
for bad,needle in [
({'regions':[{'id':1,'role':'STATE_BADGE','bbox':[10,20,30,10],'decision':{'adopted':True,'source':'TARGETED_REREAD','text':'Ver detalle'}}]},'role_mismatch'),
({'regions':[{'id':1,'role':'ROW_ACTION','bbox':[11,20,30,10],'decision':{'adopted':True,'source':'TARGETED_REREAD','text':'Ver detalle'}}]},'bbox_mismatch'),
({'regions':[{'id':1,'role':'ROW_ACTION','bbox':[10,20,30,10],'decision':{'adopted':True,'source':'TARGETED_REREAD','text':''}}]},'adopted_empty')]:
 try:o.apply_overlay(base,bad);raise AssertionError
 except ValueError as e:assert needle in str(e)
print('REREAD_OVERLAY_V3_TESTS_PASS 8/8')
