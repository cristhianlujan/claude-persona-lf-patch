#!/usr/bin/env python3
from p0_visual_grader_core_v4 import *
from p0_independent_omission_sweep_v4 import validate_sweep_receipt

def _horizontal_gap(a:dict,b:dict)->int:
 if a.get('x',0)<=b.get('x',0):return int(b.get('x',0)-(a.get('x',0)+a.get('width',0)))
 return int(a.get('x',0)-(b.get('x',0)+b.get('width',0)))
def _vertical_overlap_ratio(a:dict,b:dict)->float:
 y1=max(a.get('y',0),b.get('y',0));y2=min(a.get('y',0)+a.get('height',0),b.get('y',0)+b.get('height',0));return max(0,y2-y1)/max(1,min(a.get('height',0),b.get('height',0)))
def _atomic_overmerge_groups(sweep:dict)->dict[str,list[dict]]:
 # One candidate must not satisfy multiple materially distinct source text observations
 # that are separated into independent horizontal UI units. Coverage alone is insufficient.
 by={}
 for o in sweep.get('observations',[]):
  if not isinstance(o,dict) or not o.get('material') or o.get('kind')!='TEXT' or o.get('match_status')!='REPRESENTED' or not o.get('matched_element_id'):continue
  by.setdefault(str(o['matched_element_id']),[]).append(o)
 out={}
 for eid,items in by.items():
  if len(items)<2:continue
  atomic=[]
  for i,a in enumerate(items):
   ra=a.get('region') or {}
   for b in items[i+1:]:
    rb=b.get('region') or {};gap=_horizontal_gap(ra,rb);same_row=_vertical_overlap_ratio(ra,rb)>=.45
    # 24 px prevents punctuation/word fragments from creating a false atomicity alarm;
    # the reader's own column splitter is stricter (>=48 px or 4x glyph height).
    if same_row and gap>=24:
     atomic=[{'observation_id':x.get('observation_id'),'text':x.get('text'),'region':x.get('region')} for x in items];break
   if atomic:break
  if atomic:out[eid]=atomic
 return out

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
 by={e.get('element_id'):e for e in els}
 for eid,observations in _atomic_overmerge_groups(sweep).items():
  e=by.get(eid)
  if e is not None:fs.append(finding(ctx,g,'ATOMIC_ELEMENT_OVERMERGE','HIGH',e,{'element_id':eid,'source_observations':observations,'invariant':'ONE_MATERIAL_UI_UNIT_PER_TEXT_ELEMENT'},'REREAD',.98,'atomic-segmentation'))
 for eid in sweep.get('unsupported_candidate_ids') or []:
  e=by.get(eid)
  if e is not None:fs.append(finding(ctx,g,'UNSUPPORTED_CANDIDATE_ELEMENT','HIGH',e,{'element_id':eid,'independent_observation_match':False},'REREAD',.95,'unsupported-candidate'))
 for eid in sweep.get('candidate_support_uncertain_ids') or []:
  e=by.get(eid)
  if e is not None:fs.append(finding(ctx,g,'UNSUPPORTED_CANDIDATE_UNCERTAIN','MEDIUM',e,{'element_id':eid,'independent_support':'UNCERTAIN'},'BLOCK',.90,'unsupported-candidate-uncertainty'))
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
 return output(ctx,g,app,app,fs)
