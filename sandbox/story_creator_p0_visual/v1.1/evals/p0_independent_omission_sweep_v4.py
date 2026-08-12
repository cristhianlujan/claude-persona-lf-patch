#!/usr/bin/env python3
from __future__ import annotations
import copy,hashlib,json,sys,tempfile
from pathlib import Path
import cv2,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_full_reader_v4 import full_reader
from p0_independent_omission_sweep_v4 import run_independent_omission_sweep,validate_sweep_receipt,_text_material,_object_material
from p0_visual_grader_core_v4 import canonical_sha
from p0_visual_graders_v4 import run_all
from p0_visual_discovery_v4 import union_findings,coverage_receipt
H='a'*64

def make_image(path:Path,variant:int=1):
 im=np.full((520,900,3),255,np.uint8)
 if variant==1:
  cv2.putText(im,'NOMBRE COMPLETO',(55,95),cv2.FONT_HERSHEY_SIMPLEX,1.15,(0,0,0),2,cv2.LINE_AA)
  cv2.putText(im,'Continuar registro',(55,180),cv2.FONT_HERSHEY_SIMPLEX,.92,(0,0,0),2,cv2.LINE_AA)
  cv2.rectangle(im,(55,250),(365,350),(0,0,0),4);cv2.circle(im,(650,300),58,(0,0,0),4);cv2.line(im,(610,410),(720,465),(0,0,0),6)
 else:
  cv2.putText(im,'CODIGO ALFA 918',(80,110),cv2.FONT_HERSHEY_SIMPLEX,1.0,(0,0,0),2,cv2.LINE_AA)
  cv2.putText(im,'Pantalla nueva',(80,205),cv2.FONT_HERSHEY_SIMPLEX,.9,(0,0,0),2,cv2.LINE_AA)
  cv2.rectangle(im,(480,75),(790,210),(0,0,0),5);cv2.circle(im,(250,365),65,(0,0,0),5)
 cv2.imwrite(str(path),im)

def make_crowded(path:Path,count:int):
 # Solid isolated objects are deliberately OCR-neutral, so the test exercises
 # the real Canny object-universe cap rather than Tesseract text exclusion.
 cols=15;rows=(count+cols-1)//cols;cell_w=52;cell_h=52
 im=np.full((rows*cell_h+30,cols*cell_w+30,3),255,np.uint8)
 for i in range(count):
  row,col=divmod(i,cols);cx=26+col*cell_w;cy=26+row*cell_h
  cv2.circle(im,(cx,cy),18,(0,0,0),-1)
 cv2.imwrite(str(path),im)

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path,source_sha,pid='P-01'):
 return full_reader(str(path),{'cycle_id':'C-01','pass_id':pid,'reader_execution_id':'R-'+pid,'source_sha256':source_sha,'remediation_state':{}})
def root_only(width:int,height:int):
 return {'width':width,'height':height,'fresh_source_read':True,'reader_origin':'SOURCE_PIXELS','elements':[{'element_id':'V4-ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1.0,'region':{'x':0,'y':0,'width':width,'height':height},'parent_id':None,'evidence_refs':['source://root'],'ocr_variants':[],'ocr_consensus_text':'','graphic_score':0.0,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True}]}
def run(candidate,sweep,source_sha,pid='P-01'):
 csha=canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'});ctx={'cycle_id':'C-01','pass_id':pid,'reader_execution_id':candidate.get('reader_execution_id','R-'+pid),'source_sha256':source_sha,'candidate_sha256':csha,'coverage_execution_id':'COV-'+pid,'independent_sweep':sweep};outs=run_all(candidate,ctx);return union_findings(outs),coverage_receipt(candidate,outs,ctx),ctx
def cats(findings):return {f['category'] for f in findings}
def drop_matched(candidate,sweep,kind):
 obs=next(o for o in sweep['observations'] if o.get('material') and o.get('kind')==kind and o.get('match_status')=='REPRESENTED' and o.get('matched_element_id'))
 victim=obs['matched_element_id'];mut=copy.deepcopy(candidate);mut['elements']=[e for e in mut['elements'] if e.get('element_id')!=victim];return mut,victim

def main():
 checks=[]
 with tempfile.TemporaryDirectory() as td:
  p=Path(td)/'base.png';make_image(p,1);s=sha(p);cand=read(p,s);sw=run_independent_omission_sweep(str(p),s,cand,execution_id='SW-A');fs,cov,ctx=run(cand,sw,s)
  assert not validate_sweep_receipt(sw,cand,ctx) and 'MATERIAL_OMISSION' not in cats(fs) and cov['coverage_pass'],(cats(fs),cov,sw);checks.append('A_COMPLETE_PASS')
  mut,_=drop_matched(cand,sw,'TEXT');swb=run_independent_omission_sweep(str(p),s,mut,execution_id='SW-B');fsb,covb,ctxb=run(mut,swb,s);assert 'MATERIAL_OMISSION' in cats(fsb) and not covb['coverage_pass'];checks.append('B_TEXT_OMISSION_MATERIAL')
  mutv,_=drop_matched(cand,sw,'VISUAL_OBJECT');swc=run_independent_omission_sweep(str(p),s,mutv,execution_id='SW-C');fsc,covc,ctxc=run(mutv,swc,s);assert 'MATERIAL_OMISSION' in cats(fsc) and not covc['coverage_pass'];checks.append('C_VISUAL_OBJECT_OMISSION')
  csha=canonical_sha({k:v for k,v in cand.items() if k!='reader_execution_id'});ctxd={'cycle_id':'C-D','pass_id':'P-D','reader_execution_id':cand['reader_execution_id'],'source_sha256':s,'candidate_sha256':csha,'coverage_execution_id':'COV-D'};outs=run_all(cand,ctxd);fd=union_findings(outs);covd=coverage_receipt(cand,outs,ctxd);assert 'OMISSION_SWEEP_INVALID' in cats(fd) and not covd['coverage_pass'];checks.append('D_MISSING_SWEEP_BLOCK')
  err=copy.deepcopy(sw);err['execution_id']='SW-E';err['status']='ERROR';err['errors']=['DETECTOR_CRASH'];fse,cove,_=run(cand,err,s,'P-E');assert 'OMISSION_SWEEP_INCOMPLETE' in cats(fse) and not cove['coverage_pass'];checks.append('E_SWEEP_ERROR_BLOCK')
  tam=copy.deepcopy(swb);full=next(r for r in tam['regions'] if r['region_id']=='FULL');full['represented_count']=full['observed_count'];fsf,covf,ctxf=run(mut,tam,s,'P-F');errs=validate_sweep_receipt(tam,mut,ctxf);assert any(x.startswith('SWEEP_REPRESENTED_COUNT_INCONSISTENT') for x in errs) and 'OMISSION_SWEEP_INVALID' in cats(fsf) and not covf['coverage_pass'];checks.append('F_TAMPERED_COUNTS_BLOCK')
  empty=copy.deepcopy(cand);root=next(e for e in empty['elements'] if not e.get('parent_id'));empty['elements']=[root];swg=run_independent_omission_sweep(str(p),s,empty,execution_id='SW-G');fsg,covg,_=run(empty,swg,s,'P-G');assert 'MATERIAL_OMISSION' in cats(fsg) and not covg['coverage_pass'] and len(swg['unrepresented_observation_ids'])>0;checks.append('G_EMPTY_CANDIDATE_FAIL')
  extra=copy.deepcopy(cand);extra['elements'].append({'element_id':'INVENTED','element_type':'TEXT','visible_text':'INVENTED CLAIM','classification':'CONFIRMED','confidence':.99,'region':{'x':700,'y':470,'width':150,'height':30},'parent_id':'V4-ROOT','evidence_refs':['candidate://invented'],'ocr_variants':['INVENTED CLAIM'],'ocr_consensus_text':'INVENTED CLAIM','graphic_score':.0,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True});swh=run_independent_omission_sweep(str(p),s,extra,execution_id='SW-H');fsh,_,_=run(extra,swh,s,'P-H');assert 'INVENTED' in swh['unsupported_candidate_ids'] and 'UNSUPPORTED_CANDIDATE_ELEMENT' in cats(fsh);checks.append('H_UNSUPPORTED_EXTRA_CANDIDATE')
  renamed=copy.deepcopy(cand);mapping={e['element_id']:'REN-'+str(i) for i,e in enumerate(renamed['elements'],1)}
  for e in renamed['elements']:
   old=e['element_id'];e['element_id']=mapping[old]
   if e.get('parent_id') in mapping:e['parent_id']=mapping[e['parent_id']]
  swi=run_independent_omission_sweep(str(p),s,renamed,execution_id='SW-I');assert not swi['unrepresented_observation_ids'] and swi['status']=='COMPLETE';checks.append('I_ID_ONLY_CHANGE_INVARIANT')
  p2=Path(td)/'novel.png';make_image(p2,2);s2=sha(p2);cand2=read(p2,s2,'P-J');swj0=run_independent_omission_sweep(str(p2),s2,cand2,execution_id='SW-J0');mutj,_=drop_matched(cand2,swj0,'TEXT');swj=run_independent_omission_sweep(str(p2),s2,mutj,execution_id='SW-J');fsj,covj,_=run(mutj,swj,s2,'P-J');assert 'MATERIAL_OMISSION' in cats(fsj) and not covj['coverage_pass'];checks.append('J_NOVEL_IMAGE_GENERALIZES')
  crowded=Path(td)/'crowded90.png';make_crowded(crowded,90);sc=sha(crowded);im=cv2.imread(str(crowded));cc=root_only(im.shape[1],im.shape[0]);swk=run_independent_omission_sweep(str(crowded),sc,cc,execution_id='SW-K');fsk,covk,ctxk=run(cc,swk,sc,'P-K');assert not validate_sweep_receipt(swk,cc,ctxk) and swk['object_sweep']['deduped_count']>60 and swk['object_sweep']['emitted_count']==60 and swk['object_sweep']['limit']==60 and swk['object_sweep']['truncated'] is True and swk['status']=='BLOCKED' and 'SWEEP_UNIVERSE_TRUNCATED' in swk['errors'] and 'OMISSION_SWEEP_INCOMPLETE' in cats(fsk) and not covk['coverage_pass'];checks.append('K_MORE_THAN_60_OBJECTS_BLOCKS')
  assert _text_material('campo largo',40.0) and not _text_material('x',40.0);checks.append('L_LOW_CONF_LONG_TEXT_RETAINED')
  assert _object_material(900) and _object_material(1199) and not _object_material(899);checks.append('M_OBJECT_900_TO_1199_RETAINED')
  assert not _text_material('e » En',55.0) and _text_material('No',55.0) and _text_material('Sí',55.0) and _text_material('DNI',55.0);checks.append('N_FRAGMENTED_SHORT_OCR_HALLUCINATION_NON_MATERIAL')
  print(json.dumps({'gate':'PASS_V4_INDEPENDENT_OMISSION_SWEEP','cases':len(checks),'results':checks,'base_observations':len([o for o in sw['observations'] if o.get('material')]),'base_represented':sum(o.get('match_status')=='REPRESENTED' for o in sw['observations'] if o.get('material')),'crowded_object_sweep':swk['object_sweep'],'materiality_policy':swk['materiality_policy']},sort_keys=True))
 return 0
if __name__=='__main__':raise SystemExit(main())
