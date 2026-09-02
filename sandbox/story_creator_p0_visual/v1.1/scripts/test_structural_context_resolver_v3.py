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

# Holdout: compact/shifted table. Estado/Acciones are intentionally left of the
# old 69%/79% viewport thresholds. Classification must follow detected headers.
shift=[]
shift += [o('Buscar',260,220,100),o('Estado',420,220,100),o('6 cargas',260,382,90)]
shift_headers=['Lote','Nombre','Archivo','Tipo','Cargado por','Fecha','Total','Válidos','Estado','Acciones']
shift_xs=[260,340,440,540,620,730,805,865,950,1080]
for t,x in zip(shift_headers,shift_xs): shift.append(o(t,x,414,80))
shift += [o('#9',260,475),o('Demo',340,475),o('x.csv',440,475),o('Carga',540,475),o('Juan',620,475),o('01/09',730,475),o('10',805,475),o('9',865,475),o('Procesado',950,475,90),o('Ver detalle',1080,475,100)]
r3=v3.classify(shift,1600,1000,{})
roles={(x['text'],x['role']) for x in r3['observations']}
assert ('Procesado','STATE_BADGE') in roles, roles
assert ('Ver detalle','ROW_ACTION') in roles, roles
assert abs(r3['geometry']['header_columns']['estado']-990) < 1, r3['geometry']['header_columns']
assert abs(r3['geometry']['header_columns']['acciones']-1120) < 1, r3['geometry']['header_columns']

print('STRUCTURAL_CONTEXT_RESOLVER_V3_TESTS_PASS 11/11')
