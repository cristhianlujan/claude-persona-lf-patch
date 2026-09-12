#!/usr/bin/env python3
from __future__ import annotations
import copy,json,os,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'evals')]
from consolidate_p0_visual_reading import Box
from run_p0_visual_judge import audit_candidate
from run_p0_visual_quality_loop import remediate_once,run_loop,validate_admission
from validate_p0_machine_visual_quality import derive
from validate_p0_human_review_packet_v3 import validate as packet_gate
from p0_machine_visual_quality_negative_suite_v2 import make_image,make_admission,baseline,remove_id,add_fake_element
def repair(image,c,config,n=3):
 t=[]
 for i in range(1,n+1):
  j=audit_candidate(image,c,execution_id=f'R-J00-{i}',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config);t.append([j['judgment'],[x['code'] for x in j['remediation_targets']]])
  if j['judgment']=='PASS':return c,j,t
  c,a=remediate_once(image,c,j,config,i);t[-1].append([x['action'] for x in a])
 return c,audit_candidate(image,c,execution_id='R-J00-F',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config),t
def audit(image,c,config,tag):return audit_candidate(image,c,execution_id=tag,identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config)
def subtree(c,eid):
 for x in [e['element_id'] for e in c['elements'] if e.get('parent_id')==eid]:subtree(c,x)
 remove_id(c,eid)
def main():
 cfg=json.loads((ROOT/'evals/p0-visual-quality-runtime-config.json').read_text())
 if os.getenv('P0_CI_ENGINEERING_REGRESSION')=='1':
  from consolidate_p0_visual_reading import runtime_versions
  cfg['dependencies']=runtime_versions();cfg['configuration_id']='P0-CI-ENGINEERING-REGRESSION-v1';cfg['calibration']['calibration_reference']='ci://engineering-regression/not-operational-quality'
 ok={};ev={}
 def rec(k,v,d=None):ok[k]=bool(v);ev[k]=d
 with tempfile.TemporaryDirectory() as d:
  d=Path(d);image=d/'x.png';make_image(image);adm=d/'a.json';make_admission(image,adm);base,j0,r0,p0=baseline(image,cfg)
  c=copy.deepcopy(base);e=next(e for e in c['elements'] if e.get('element_type')=='LABEL' and e.get('visible_text')=='Nombre');e['visible_text']='© Nombre';b=audit(image,c,cfg,'R1');_,a,t=repair(image,c,cfg);rec('R01_icon_to_text_confusion',any(x['code']=='ICON_TEXT_CONFUSION' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);cb=next(e for e in c['elements'] if e['element_type']=='CHECKBOX');r,p,refs=cb['region'],cb['parent_id'],cb['evidence_refs'];remove_id(c,cb['element_id']);c['elements'].append({'element_id':'O','source_image_ref':'SYNTH-P0-NEGATIVE','parent_id':p,'region':r,'element_type':'TEXT','visible_text':'O','semantic_role':'visible_copy','visual_state':'STATIC_VISIBLE','classification':'CONFIRMED','confidence':.99,'evidence_refs':refs,'source_observation_refs':[],'uncertainty_codes':[],'machine_resolution_status':'RESOLVED'});c['ui_structure']['visual_containment_tree']['edges'].append({'parent':p,'child':'O'});b=audit(image,c,cfg,'R2');_,a,t=repair(image,c,cfg);rec('R02_checkbox_to_O_confusion',any(x['code']=='CHECKBOX_TEXT_CONFUSION' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);e=next(e for e in c['elements'] if e.get('element_type')=='LABEL' and e.get('visible_text')=='Nombre');e['visible_text']='N0mbre';b=audit(image,c,cfg,'R3');_,a,t=repair(image,c,cfg);rec('R03_punctuation_accent_character_error',any(x['code']=='TEXT_DISAGREEMENT' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);parents={e['element_id']:e for e in c['elements']};x=next(e for e in c['elements'] if e['element_type']=='ICON' and parents.get(e['parent_id'],{}).get('element_type') in {'INPUT','SELECT','BUTTON'});remove_id(c,x['element_id']);b=audit(image,c,cfg,'R4');_,a,t=repair(image,c,cfg);rec('R04_input_children_missing',any(x['code']=='CONTROL_ICON_CHILD_MISSING' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);remove_id(c,next(e['element_id'] for e in c['elements'] if e['element_type']=='PROGRESS_INDICATOR'));b=audit(image,c,cfg,'R5');_,a,t=repair(image,c,cfg);rec('R05_progress_indicator_omitted',any(x['code']=='AUDIT_ONLY_PROGRESS' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);root=next(e['element_id'] for e in c['elements'] if e['parent_id'] is None)
  for e in c['elements']:
   if e['element_id']!=root:e['parent_id']=root
  c['ui_structure']['visual_containment_tree']['edges']=[{'parent':root,'child':e['element_id']} for e in c['elements'] if e['element_id']!=root];b=audit(image,c,cfg,'R6');_,a,t=repair(image,c,cfg);rec('R06_flat_hierarchy',any(x['code']=='STRUCTURE_REBUILD_REQUIRED' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);subtree(c,next(e['element_id'] for e in c['elements'] if e['element_type']=='INPUT'));b=audit(image,c,cfg,'R7');_,a,t=repair(image,c,cfg);rec('R07_audit_only_material_element',any(x.get('material') for x in b['audit_only']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);h=next(e['element_id'] for e in c['elements'] if e.get('semantic_role')=='header');add_fake_element(c,'ICON',Box(740,15,20,20),h);b=audit(image,c,cfg,'R8');_,a,t=repair(image,c,cfg);rec('R08_reader_only_unsupported',bool(b['unsupported_claims']) and a['judgment']=='PASS',t)
  c=copy.deepcopy(base);x=next(e for e in c['elements'] if e['element_type']=='BUTTON');x['element_type']='INPUT';x['semantic_role']='form_control';b=audit(image,c,cfg,'R9');_,a,t=repair(image,c,cfg);rec('R09_reader_judge_contradiction',bool(b['contradictions']) and a['judgment']=='PASS',t)
  import run_p0_visual_quality_loop as loop;old=loop.remediate_once
  try:
   loop.remediate_once=lambda *a,**k:(copy.deepcopy(a[1]),[{'action':'NO_STATE_CHANGE'}]);z=run_loop(image_path=image,admission_path=adm,processing_manifest_path=None,source_image_ref='SYNTH-P0-NEGATIVE',config=cfg,output_dir=d/'r10',execution_id='R10',judge_identity='P0_VISUAL_JUDGE');rec('R10_remediation_no_progress_loop',z['result']=='BLOCKED_MAX_REMEDIATION',z['result'])
  finally:loop.remediate_once=old
  j=audit_candidate(image,base,execution_id=base['execution_id'],identity='P0_VISUAL_READER',reader_execution_id=base['execution_id'],config=cfg);rec('R11_same_reader_judge_identity',j['judgment']=='BLOCKED',j['findings'])
  r=copy.deepcopy(r0);r['human_review_ready']=False;g=derive(r,base,j0);rec('R12_quality_pass_flag_edited',not g['human_review_ready'],g)
  p=copy.deepcopy(p0);p['machine_quality_report_sha256']='f'*64;v=packet_gate(p,r0,base,j0);rec('R13_machine_report_sha_mismatch',not v['human_review_ready'],v)
  x=json.loads(adm.read_text());x['raw_bytes_sha256']='0'*64;bad=d/'bad.json';bad.write_text(json.dumps(x));v=validate_admission(image,bad,None);rec('R14_source_admission_mismatch',not v['pass'],v['checks'])
  c=copy.deepcopy(base);remove_id(c,next(e['element_id'] for e in c['elements'] if e['element_type']=='CHECKBOX'));b=audit(image,c,cfg,'R15');_,a,t=repair(image,c,cfg);rec('R15_small_element_missed_without_adaptive_repair',any(x['code']=='AUDIT_ONLY_CHECKBOX' for x in b['remediation_targets']) and a['judgment']=='PASS',t)
 failed=[k for k,v in ok.items() if not v];out={'schema_version':'p0-runtime-regression-suite/v1','result':'PASS_WITH_EVIDENCE' if not failed else 'BLOCKED','required':15,'executed':len(ok),'passed':sum(ok.values()),'tests':ok,'failed':failed,'evidence':ev};print(json.dumps(out,sort_keys=True));return 0 if not failed else 2
if __name__=='__main__':raise SystemExit(main())
