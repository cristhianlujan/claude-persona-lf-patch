#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('targeted_reread_reconciler_v3.py')
s=importlib.util.spec_from_file_location('r',p); r=importlib.util.module_from_spec(s); s.loader.exec_module(r)
a=r.reconcile('detate','Ver detalle','ROW_ACTION'); assert a['adopted'] and a['text']=='Ver detalle'
b=r.reconcile('Mas','=','FILTER_BAR'); assert not b['adopted'] and b['text']=='Mas'
c=r.reconcile('Rechazaco','@ Rechazado','STATE_BADGE'); assert c['adopted'] and c['text']=='@ Rechazado'
d=r.reconcile('Original','e y Original','ROW_ACTION'); assert not d['adopted']
assert r.reconcile('','', 'ROW_ACTION')['text']==''
e=r.reconcile('pla','esplázat','TABLE_SUMMARY'); assert not e['adopted'] and e['text']=='pla'
f=r.reconcile('timpiarfitros','Limpiar filtros','FILTER_BAR'); assert f['adopted'] and f['text']=='Limpiar filtros'
g=r.reconcile('Ordenar','Ordenar por Fecha nor','FILTER_BAR'); assert g['adopted'] and g['text']=='Ordenar por' and g['visible_span_selected']
h=r.reconcile('ord','x y por','FILTER_BAR'); assert h['text']=='ord' and not h['adopted']
i=r.best_visible_span('foo Rechazado bar','STATE_BADGE'); assert i[0]=='Rechazado'
for original,reread,role in [('x','foo Ver detalle bar','ROW_ACTION'),('x','foo Limpiar filtros bar','FILTER_BAR'),('x','foo Procesado con observaciones bar','STATE_BADGE')]:
    out=r.reconcile(original,reread,role)
    assert not out['adopted'] or all(tok in reread.split() for tok in out['text'].split())
print('TARGETED_REREAD_RECONCILER_V3_TESTS_PASS 11/11')
