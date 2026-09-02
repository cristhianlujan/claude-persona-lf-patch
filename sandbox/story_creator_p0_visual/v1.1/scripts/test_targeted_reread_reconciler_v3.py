#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('targeted_reread_reconciler_v3.py')
s=importlib.util.spec_from_file_location('r',p); r=importlib.util.module_from_spec(s); s.loader.exec_module(r)
a=r.reconcile('detate','Ver detalle','ROW_ACTION'); assert a['adopted'] and a['text']=='Ver detalle'
b=r.reconcile('Mas','=','FILTER_BAR'); assert not b['adopted'] and b['text']=='Mas'
c=r.reconcile('Rechazaco','@ Rechazado','STATE_BADGE'); assert c['adopted']
d=r.reconcile('Original','e y Original','ROW_ACTION'); assert not d['adopted']
assert r.reconcile('','', 'ROW_ACTION')['text']==''
print('TARGETED_REREAD_RECONCILER_V3_TESTS_PASS 5/5')
