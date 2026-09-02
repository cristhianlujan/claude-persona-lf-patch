#!/usr/bin/env python3
import importlib.util
from pathlib import Path

MOD=Path(__file__).with_name('structural_context_resolver_v3.py')
spec=importlib.util.spec_from_file_location('v3', MOD)
v3=importlib.util.module_from_spec(spec); spec.loader.exec_module(v3)

def o(text,x,y,w=70,h=16,conf=95):
    return {'text':text,'bbox':[x,y,w,h],'conf':conf}

obs=[]
obs += [o('LF',20,25),o('Ayuda',1400,25),o('Cargas',30,140),o('Historial de cargas',280,130,180)]
for i,t in enumerate(['Buscar','Estado','Tipo de carga','Cargado por','Aprobación']): obs.append(o(t,280+i*180,220,120))
for i,t in enumerate(['Desde','Hasta','Ordenar por','Dirección']): obs.append(o(t,280+i*200,290,120))
obs += [o('6 cargas',280,382,90)]
headers=['Lote','Nombre','Archivo','Tipo','Cargado por','Fecha','Total','Válidos','Estado','Acciones']
xs=[280,370,500,640,730,870,960,1040,1130,1310]
for t,x in zip(headers,xs): obs.append(o(t,x,414,90))
for yy in (475,531):
    obs += [o('#000184',280,yy),o('Cartera agosto',370,yy,120),o('archivo.csv',500,yy),o('Carga',640,yy),o('Juan Díaz',730,yy),o('01/09',870,yy),o('100',960,yy),o('96',1040,yy),o('Procesado',1130,yy,100,16,55),o('Ver detalle',1310,yy,100,16,50)]
obs += [o('1',800,840),o('2',840,840)]
ctx={'horizontal_overflow_observed':True,'canonical_table_fields':['Lote','Nombre','Observados','Rechazados','Aprobado por']}
r=v3.classify(obs,1600,1000,ctx)
assert r['counts']['DYNAMIC_DATA'] >= 16, r['counts']
assert r['counts']['STATE_BADGE'] == 2, r['counts']
assert r['counts']['ROW_ACTION'] == 2, r['counts']
assert r['residual_count'] == 4, r['residual']
vis={x['field']:x for x in r['canonical_visibility']}
assert vis['Lote']['status']=='VISIBLE'
for k in ['Observados','Rechazados','Aprobado por']:
    assert vis[k]['status']=='NOT_CURRENTLY_VISIBLE' and vis[k]['material_omission'] is False
r2=v3.classify(obs,1600,1000,{'horizontal_overflow_observed':False,'canonical_table_fields':['Aprobado por']})
assert r2['canonical_visibility'][0]['status']=='UNKNOWN_VISIBILITY'
assert r2['canonical_visibility'][0]['material_omission'] is None
print('STRUCTURAL_CONTEXT_RESOLVER_V3_TESTS_PASS 7/7')
