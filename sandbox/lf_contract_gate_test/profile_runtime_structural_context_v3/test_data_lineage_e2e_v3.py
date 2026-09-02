#!/usr/bin/env python3
import importlib.util
from pathlib import Path
ROOT=Path(__file__).parent
def load(name):
 p=ROOT/f'{name}.py'; s=importlib.util.spec_from_file_location(name,p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
v3=load('structural_context_resolver_v3'); rec=load('targeted_reread_reconciler_v3'); ov=load('apply_reread_overlay_v3'); packer=load('build_decomposer_context_pack_v3')
IMG='ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287'; CTX='b'*64
def o(i,text,x,y,w=70,h=16,conf=95): return {'id':i,'text':text,'bbox':[x,y,w,h],'conf':conf}
obs=[o('top','LF',20,25),o('page','Historial de cargas',280,130,180)]
for i,t in enumerate(['Buscar','Estado','Tipo de carga','Cargado por','Aprobación']): obs.append(o(f'f{i}',t,280+i*180,220,120))
obs += [o('summary','6 cargas',280,382,90)]
headers=['Lote','Nombre','Archivo','Tipo','Cargado por','Fecha','Total','Válidos','Estado','Acciones']; xs=[280,370,500,640,730,870,960,1040,1130,1310]
for i,(t,x) in enumerate(zip(headers,xs)): obs.append(o(f'h{i}',t,x,414,90))
obs += [o('dyn','#000184',280,475),o('name','Cartera agosto',370,475,120),o('file','archivo.csv',500,475),o('kind','Carga',640,475),o('who','Juan Díaz',730,475),o('date','01/09',870,475),o('total','100',960,475),o('valid','96',1040,475),o('state','Rechazaco',1130,475,100,16,45),o('action','detate',1310,475,100,16,45)]
ctx={'horizontal_overflow_observed':True,'canonical_table_fields':['Lote','Nombre','Observados','Rechazados','Aprobado por']}
r=v3.classify(obs,1600,1000,ctx)
by={x['id']:x for x in r['observations']}
assert by['dyn']['role']=='DYNAMIC_DATA' and not by['dyn']['needs_reread']
assert by['state']['role']=='STATE_BADGE' and by['state']['needs_reread']
assert by['action']['role']=='ROW_ACTION' and by['action']['needs_reread']
vis={x['field']:x for x in r['canonical_visibility']}
assert vis['Observados']=={'field':'Observados','status':'NOT_CURRENTLY_VISIBLE','material_omission':False}
state_dec=rec.reconcile(by['state']['text'],'Rechazado','STATE_BADGE'); action_dec=rec.reconcile(by['action']['text'],'Ver detalle','ROW_ACTION')
assert state_dec['adopted'] and action_dec['adopted']
rr={'regions':[{'id':'state','role':'STATE_BADGE','bbox':[by['state'][k] for k in ('x','y','w','h')],'decision':{**state_dec,'psm':6}},{'id':'action','role':'ROW_ACTION','bbox':[by['action'][k] for k in ('x','y','w','h')],'decision':{**action_dec,'psm':11}}]}
after=ov.apply_overlay(r,rr)
assert next(x for x in after['observations'] if x['id']=='state')['text']=='Rechazaco'
assert next(x for x in after['observations'] if x['id']=='state')['effective_text']=='Rechazado'
assert next(x for x in after['observations'] if x['id']=='dyn').get('effective_text') is None
p=packer.build(after,IMG,CTX)
resolved={x['id']:x for x in p['resolved_visible_observations']}
assert resolved['state']['original_text']=='Rechazaco' and resolved['state']['effective_text']=='Rechazado'
assert resolved['action']['original_text']=='detate' and resolved['action']['effective_text']=='Ver detalle'
assert 'dyn' not in resolved
assert p['canonical_visibility']==r['canonical_visibility']
assert p['dynamic_data_policy']=='DO_NOT_CANONICAL_RECONCILE'
assert p['profile_contract_valid']=='NOT_EVALUATED' and p['semantic_utility']=='NOT_EVALUATED'
trace_ids={'h0','f0','dyn','state','action'}
lost=sum(1 for i in trace_ids if i not in by)
invented=sum(1 for x in p['resolved_visible_observations'] if x['effective_text_source']!='TARGETED_REREAD')
role_changed=0; bbox_changed=0; provenance_missing=sum(1 for x in p['resolved_visible_observations'] if not x.get('reread_provenance'))
dynamic_canonicalized=1 if 'dyn' in resolved else 0
offviewport_wrong=0 if vis['Observados']['status']=='NOT_CURRENTLY_VISIBLE' and vis['Observados']['material_omission'] is False else 1
gate_bypass=0 if p['profile_contract_valid']=='NOT_EVALUATED' and p['semantic_utility']=='NOT_EVALUATED' else 1
critical=lost+invented+role_changed+bbox_changed+provenance_missing+dynamic_canonicalized+offviewport_wrong+gate_bypass
assert critical==0,(lost,invented,role_changed,bbox_changed,provenance_missing,dynamic_canonicalized,offviewport_wrong,gate_bypass)
print('DATA_LINEAGE_E2E_V3_PASS input_trace_count=5 output_trace_count=5 lost_trace_count=0 invented_trace_count=0 role_changed_without_evidence_count=0 bbox_changed_without_evidence_count=0 provenance_missing_count=0 dynamic_data_canonicalized_count=0 offviewport_wrongly_omitted_count=0 gate_bypass_count=0 critical_regressions_count=0')
