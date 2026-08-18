#!/usr/bin/env python3
from __future__ import annotations
import copy
import cv2,pytesseract
from p0_multiscreen_structural_generalization_v1 import full_reader
from p0_icon_structural_roles_v1 import reconcile_icon_structural_roles
from p0_independent_omission_sweep_v4 import run_independent_omission_sweep
from p0_visual_graders_v4 import run_all
TRACE={'readers':[],'grader_runs':[],'omission_sweeps':[],'remediations':[],'targeted':[]}
def reset_trace():
 for v in TRACE.values():v.clear()
def traced_sweep(source_path,expected_sha,candidate,*,execution_id):
 sw=run_independent_omission_sweep(source_path,expected_sha,candidate,execution_id=execution_id);TRACE['omission_sweeps'].append(copy.deepcopy(sw));return sw
def traced_grader_runner(candidate,ctx):
 outs=run_all(candidate,ctx);TRACE['grader_runs'].append({'ctx':copy.deepcopy(ctx),'outputs':copy.deepcopy(outs)});return outs
def make_grader_runner(source_path=None):return traced_grader_runner
def _region_overlap(a,b):
 ax1,ay1=float(a.get('x',0)),float(a.get('y',0));ax2,ay2=ax1+float(a.get('width',0)),ay1+float(a.get('height',0))
 bx1,by1=float(b.get('x',0)),float(b.get('y',0));bx2,by2=bx1+float(b.get('width',0)),by1+float(b.get('height',0))
 inter=max(0.0,min(ax2,bx2)-max(ax1,bx1))*max(0.0,min(ay2,by2)-max(ay1,by1));aa=max(1.0,(ax2-ax1)*(ay2-ay1));bb=max(1.0,(bx2-bx1)*(by2-by1));return max(inter/aa,inter/bb)
def _dedupe_regions(items):
 out=[]
 for item in items:
  r=item.get('region') if isinstance(item,dict) and isinstance(item.get('region'),dict) else item
  if not isinstance(r,dict):continue
  row={'region':{k:int(r.get(k,0)) for k in ('x','y','width','height')},'source_category':str(item.get('source_category') or 'SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT') if isinstance(item,dict) else 'SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT'}
  if not any(_region_overlap(row['region'],existing['region'])>=.80 for existing in out):out.append(row)
 return out
def _apply_same_family_consensus_selection_guard(candidate):
 out=copy.deepcopy(candidate)
 for element in out.get('elements',[]):
  if element.get('element_type')!='TEXT' or element.get('classification')!='INFERRED':continue
  if element.get('ocr_consensus_source')!='OCR_PSM_CONSENSUS' or element.get('independent_redetection') is not False:continue
  variants=[str(v or '').strip() for v in (element.get('ocr_variants') or [])]
  if not variants or not variants[0]:continue
  primary=variants[0];selected=str(element.get('visible_text') or '').strip()
  if not selected or primary.casefold()==selected.casefold():continue
  confidence=float(element.get('confidence') or 0.0)
  if confidence<0.90:continue
  element['visible_text']=primary
  element['same_family_consensus_selection_guard']={
   'code':'PRESERVE_HIGH_CONFIDENCE_PRIMARY_ON_SAME_FAMILY_DISAGREEMENT',
   'primary_text':primary,'same_family_consensus_text':selected,'primary_confidence':confidence,
   'basis':'SAME_FAMILY_CONSENSUS_CANNOT_OVERRIDE_HIGH_CONFIDENCE_PRIMARY_WITHOUT_ORTHOGONAL_EVIDENCE'
  }
 return out
def _apply_remediation_state(candidate,state):
 suppressed=_dedupe_regions((state or {}).get('unsupported_short_text_regions') or [])
 if not suppressed:return candidate
 out=copy.deepcopy(candidate);uncertainties=list(out.get('uncertainties') or [])
 for element in out.get('elements',[]):
  if element.get('classification')!='INFERRED' or element.get('element_type')!='TEXT':continue
  text=str(element.get('visible_text') or '').strip();clean=''.join(ch for ch in text if ch.isalnum())
  if not (2<=len(clean)<=3 and clean.isdigit()):continue
  region=element.get('region') or {};matched=next((item for item in suppressed if _region_overlap(region,item['region'])>=.35),None)
  if matched is None:continue
  element['remediation_disposition']={'code':'RECLASSIFIED_UNSUPPORTED_SHORT_TEXT','source_category':matched['source_category'],'original_visible_text':text,'source_region':copy.deepcopy(matched['region'])}
  element['visible_text']=None;element['element_type']='ICON_OR_GLYPH';element['semantic_role']='visual_fragment';element['subcomponent_role']='GLYPH';element['ocr_consensus_text']='';element['independent_redetection']=False;element['redetection_status']='RECLASSIFIED_UNSUPPORTED_SHORT_TEXT';element['graphic_score']=max(.82,float(element.get('graphic_score',0) or 0))
  text_only_codes={'OCR_DISAGREEMENT','TEXT_GROUPING_DISAGREEMENT'}
  out['reader_uncertainties']=[u for u in list(out.get('reader_uncertainties') or []) if not (u.get('element_id')==element.get('element_id') and u.get('code') in text_only_codes)]
  uncertainties.append({'element_id':element.get('element_id'),'code':'UNSUPPORTED_SHORT_TEXT_RECLASSIFIED','region':copy.deepcopy(region),'source_category':matched['source_category']})
 out['uncertainties']=uncertainties
 return out
def traced_reader(path,ctx):
 c=full_reader(path,ctx);c=_apply_same_family_consensus_selection_guard(c);c=_apply_remediation_state(c,ctx.get('remediation_state') or {});c=reconcile_icon_structural_roles(c);TRACE['readers'].append(copy.deepcopy(c));return c
def remediator(candidate,findings,state):
 actions=[];seen=set();state=dict(state);state['strict_mode']=True
 suppressed=_dedupe_regions(state.get('unsupported_short_text_regions') or [])
 material_regions=[f.get('region') or {} for f in findings if f.get('category')=='MATERIAL_OMISSION']
 if material_regions:
  suppressed=[item for item in suppressed if not any(_region_overlap(item['region'],region)>=.35 for region in material_regions)]
 for f in findings:
  category=f['category'];region=f.get('region') or {'x':0,'y':0,'width':0,'height':0}
  if category=='SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT':
   suppressed=_dedupe_regions(suppressed+[{'region':region,'source_category':category}]);action='RECLASSIFY_UNSUPPORTED_SHORT_TEXT'
  elif category=='MATERIAL_OMISSION':action='RESTORE_MATERIAL_TEXT_IF_SUPPRESSED'
  else:action='STRICT_CONSENSUS_REREAD'
  if category in seen:continue
  seen.add(category);actions.append({'category':category,'region':region,'action':action,'affected_findings':sum(x['category']==category for x in findings)})
 if suppressed:state['unsupported_short_text_regions']=suppressed
 else:state.pop('unsupported_short_text_regions',None)
 TRACE['remediations'].append({'finding_count':len(findings),'categories':sorted(seen),'actions':copy.deepcopy(actions),'unsupported_short_text_region_count':len(suppressed)});return state,actions
def targeted(source_path,actions,ctx):
 im=cv2.imread(source_path);verified=[]
 if im is None:return {'verified':False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':0,'reread_scope':'SOURCE_DECODE_FAILED'}
 for a in actions:
  r=a['region'];x=max(0,int(r.get('x',0))-8);y=max(0,int(r.get('y',0))-8);x2=min(im.shape[1],int(r.get('x',0))+int(r.get('width',0))+8);y2=min(im.shape[0],int(r.get('y',0))+int(r.get('height',0))+8);verified.append(bool(x2>x and y2>y and im[y:y2,x:x2].size))
 if verified and all(verified):
  for psm in (6,11):pytesseract.image_to_string(im,lang='spa',config=f'--psm {psm}')
 out={'verified':all(verified) if verified else False,'action_count':len(actions),'source_sha256':ctx['source_sha256'],'reread_execution':'TARGET-'+ctx['pass_id'],'region_verifications':len(verified),'reread_scope':'SELECTED_REGIONS_CORROBORATED_BY_FRESH_SOURCE_PSM6_PSM11'};TRACE['targeted'].append(copy.deepcopy(out));return out