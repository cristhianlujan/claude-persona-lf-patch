#!/usr/bin/env python3
from p0_visual_grader_core_v4 import *
def j_complete(candidate:dict,ctx:dict)->dict:
 g='J-COMPLETE';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];regions=[]
 for r in candidate.get('coverage_map',[]) or [{'region_id':'FULL','material':True,'observed_count':len(els),'represented_count':len(els)}]:
  if not r.get('material',True):continue
  regions.append(str(r.get('region_id','UNKNOWN')))
  if int(r.get('represented_count',0))<int(r.get('observed_count',0)):fs.append(finding(ctx,g,'MATERIAL_OMISSION','HIGH',None,{'region_id':r.get('region_id'),'observed_count':r.get('observed_count'),'represented_count':r.get('represented_count')},'REREAD',.95,'omission-sweep'))
  if r.get('sweep_status') in {'INCOMPLETE','ERROR'}:fs.append(finding(ctx,g,'OMISSION_SWEEP_INCOMPLETE','HIGH',None,{'region_id':r.get('region_id'),'sweep_status':r.get('sweep_status')},'BLOCK',.99,'coverage-gap'))
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
