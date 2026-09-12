#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('batched_targeted_reread_v3.py')
s=importlib.util.spec_from_file_location('b',p); b=importlib.util.module_from_spec(s); s.loader.exec_module(b)
spans=[(0,40),(80,120)]
words=[
 {'text':'Ver','left':5,'top':10,'width':20,'height':10},
 {'text':'detalle','left':30,'top':11,'width':30,'height':10},
 {'text':'NO_LEAK','left':1,'top':35,'width':20,'height':50},
 {'text':'Rechazado','left':10,'top':90,'width':50,'height':12},]
a=b.assign_words_to_spans(words,spans); assert [w['text'] for w in a[0]]==['Ver','detalle']; assert [w['text'] for w in a[1]]==['Rechazado']
assert b.reconstruct_region_text(a[0])=='Ver detalle'; assert b.reconstruct_region_text(a[1])=='Rechazado'
assert b.reconstruct_region_text([{'text':'detalle','left':30,'top':11,'height':10},{'text':'Ver','left':5,'top':10,'height':12}])=='Ver detalle'
def fake(original,text,role):
    fit={'bad':.2,'good':.91,'better':.97}.get(text,.1); adopt=fit>=.7
    return {'text':text if adopt else original,'source':'TARGETED_REREAD' if adopt else 'ORIGINAL_OCR','reread_role_fit':fit,'adopted':adopt}
d=b.select_best_candidate('orig','ROW_ACTION',{6:'bad',7:'good',11:'better'},fake); assert d['adopted'] and d['text']=='better' and d['psm']==11
d=b.select_best_candidate('orig','ROW_ACTION',{6:'bad'},fake); assert not d['adopted'] and d['text']=='orig'
print('BATCHED_TARGETED_REREAD_V3_TESTS_PASS 6/6')
