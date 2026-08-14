#!/usr/bin/env python3
from p0_visual_grader_core_v4 import *
from p0_independent_omission_sweep_v4 import validate_sweep_receipt
from p0_visual_atomicity_v4 import evidence_purity_issues, exclusive_partition_issues

def j_complete(candidate:dict,ctx:dict)->dict:
 g='J-COMPLETE';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];sweep=ctx.get('independent_sweep');errors=validate_sweep_receipt(sweep,candidate,ctx)
 if errors:fs.append(finding(ctx,g,'OMISSION_SWEEP_INVALID','HIGH',None,{'errors':errors},'BLOCK',.99,'independent-sweep-validation'))
 if not isinstance(sweep,dict):return output(ctx,g,app,app,fs,['FULL'])
 regions=[str(r.get('region_id')) for r in sweep.get('regions',[]) if r.get('region_id')]
 if sweep.get('status') in {'INCOMPLETE','ERROR','BLOCKED'}:fs.append(finding(ctx,g,'OMISSION_SWEEP_INCOMPLETE','HIGH',None,{'status':sweep.get('status'),'errors':sweep.get('errors') or []},'BLOCK',.99,'independent-sweep-status'))
 for o in sweep.get('observations',[]):
  if not o.get('material'):continue
  pseudo={'element_id':None,'region':o.get('region') or {},'evidence_refs':o.get('evidence_refs') or []}
  if o.get('match_status')=='UNREPRESENTED':fs.append(finding(ctx,g,'MATERIAL_OMISSION','HIGH',pseudo,{'observation_id':o.get('observation_id'),'kind':o.get('kind'),'text':o.get('text'),'match_status':'UNREPRESENTED'},'REREAD',.96,'independent-omission-sweep'))
  elif o.get('match_status')=='UNCERTAIN':fs.append(finding(ctx,g,'OMISSION_SWEEP_UNCERTAIN','MEDIUM',pseudo,{'observation_id':o.get('observation_id'),'kind':o.get('kind'),'text':o.get('text')},'BLOCK',.90,'independent-omission-uncertainty'))
 for group in sweep.get('repeated_control_groups') or []:
  if group.get('status')!='PASS':
   pseudo={'element_id':None,'region':{},'evidence_refs':[]}
   fs.append(finding(ctx,g,'REPEATED_CONTROL_CARDINALITY_MISMATCH','HIGH',pseudo,group,'REREAD',.99,'independent-control-cardinality'))
 by={e.get('element_id'):e for e in els}
 for eid in sweep.get('unsupported_candidate_ids') or []:
  e=by.get(eid)
  if e is not None:fs.append(finding(ctx,g,'UNSUPPORTED_CANDIDATE_ELEMENT','HIGH',e,{'element_id':eid,'independent_observation_match':False},'REREAD',.95,'unsupported-candidate'))
 for eid in sweep.get('candidate_support_uncertain_ids') or []:
  e=by.get(eid)
  if e is not None:fs.append(finding(ctx,g,'UNSUPPORTED_CANDIDATE_UNCERTAIN','MEDIUM',e,{'element_id':eid,'independent_support':'UNCERTAIN'},'BLOCK',.90,'unsupported-candidate-uncertainty'))
 # EKB-P0-020: a short inferred numeric OCR token must not become harmless
 # merely because multiple reads from the same Tesseract family repeat it.
 # Require material contextual support from the independent source sweep;
 # otherwise keep the candidate fail-closed for reread/human review.
 supported_short_ids={
  o.get('matched_element_id') for o in sweep.get('observations',[])
  if o.get('kind')=='TEXT' and o.get('material') is True and o.get('match_status')=='REPRESENTED'
 }
 for e in els:
  if e.get('classification')!='INFERRED' or e.get('element_type')!='TEXT':continue
  txt=str(e.get('visible_text') or '').strip();clean=''.join(ch for ch in txt if ch.isalnum())
  if 2<=len(clean)<=3 and clean.isdigit() and e.get('element_id') not in supported_short_ids:
   fs.append(finding(ctx,g,'SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT','MEDIUM',e,{'text':txt,'independent_material_text_match':False,'same_family_ocr_is_not_independent_support':True},'BLOCK',.95,'short-text-materiality-support'))
 return output(ctx,g,app,app,fs,regions or ['FULL'])

def j_geometry(candidate:dict,ctx:dict)->dict:
 g='J-GEOMETRY';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];W=int(candidate.get('width',0));H=int(candidate.get('height',0));by={e['element_id']:e for e in els}
 for e in els:
  r=bbox(e)
  if min(r.get('x',0),r.get('y',0),r.get('width',0),r.get('height',0))<0 or (W and r['x']+r['width']>W) or (H and r['y']+r['height']>H):fs.append(finding(ctx,g,'BBOX_OUT_OF_BOUNDS','HIGH',e,{'bbox':r,'viewport':[W,H]},'AUTO_REMEDIATE',.99,'geometry-bounds'))
  if e.get('bbox_reproducible') is False:fs.append(finding(ctx,g,'BBOX_NOT_REPRODUCIBLE','MEDIUM',e,{'bbox':r},'REREAD',.92,'geometry-reproducibility'))
  p=by.get(e.get('parent_id'))
  if p and not inside(e,p):fs.append(finding(ctx,g,'PARENT_CONTAINMENT_MISMATCH','MEDIUM',e,{'parent_id':p['element_id'],'child_bbox':r,'parent_bbox':bbox(p)},'AUTO_REMEDIATE',.93,'containment'))
 return output(ctx,g,app,app,fs)

def j_structure(candidate:dict,ctx:dict)->dict:
 g='J-STRUCTURE';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];by={e['element_id']:e for e in els};roots=[e for e in els if not e.get('parent_id')]
 if len(roots)!=1:fs.append(finding(ctx,g,'ROOT_CARDINALITY_INVALID','HIGH',None,{'root_count':len(roots)},'BLOCK',.99,'structure-root'))
 for e in els:
  pid=e.get('parent_id')
  if pid and pid not in by:fs.append(finding(ctx,g,'PARENT_MISSING','HIGH',e,{'parent_id':pid},'AUTO_REMEDIATE',.99,'structure-parent'))
  seen={e['element_id']};cur=e
  for _ in range(len(els)+1):
   pid=cur.get('parent_id')
   if not pid or pid not in by:break
   if pid in seen:fs.append(finding(ctx,g,'PARENT_CYCLE','CRITICAL',e,{'cycle_at':pid},'BLOCK',1.0,'structure-cycle'));break
   seen.add(pid);cur=by[pid]
 for issue in evidence_purity_issues(els):
  element=by.get(issue.get('element_id'))
  fs.append(finding(ctx,g,'SHARED_EVIDENCE_VIOLATION','HIGH',element,issue,'REREAD',.99,'exclusive-evidence-partition'))
 for issue in exclusive_partition_issues(els):
  element=by.get((issue.get('element_ids') or [None])[0])
  fs.append(finding(ctx,g,issue['code'],'HIGH',element,issue,'REREAD',.99,'exclusive-evidence-partition'))
 return output(ctx,g,app,app,fs)