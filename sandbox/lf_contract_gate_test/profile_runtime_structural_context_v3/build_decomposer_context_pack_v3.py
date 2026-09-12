#!/usr/bin/env python3
import hashlib,json,re
SHA=re.compile(r'^[0-9a-f]{64}$')
ALLOWED_OVERLAY_ROLES={'PAGE_HEADER','PAGE_ACTIONS','FILTER_BAR','TABLE_SUMMARY','TABLE_HEADER','STATE_BADGE','ROW_ACTION'}
def digest(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def _resolved_visible_observations(result):
 out=[]
 for o in result.get('observations') or []:
  if 'effective_text' not in o: continue
  role=o.get('role')
  if role not in ALLOWED_OVERLAY_ROLES: raise ValueError('overlay_role_not_allowed')
  if o.get('effective_text_source')!='TARGETED_REREAD': raise ValueError('overlay_source_invalid')
  original=str(o.get('text','')).strip(); effective=str(o.get('effective_text','')).strip()
  if not original or not effective: raise ValueError('overlay_text_missing')
  bbox=[float(o.get(k,0)) for k in ('x','y','w','h')]
  if bbox[2]<=0 or bbox[3]<=0: raise ValueError('overlay_bbox_invalid')
  out.append({'id':o.get('id'),'role':role,'bbox':bbox,'original_text':original,'effective_text':effective,'effective_text_source':'TARGETED_REREAD','reread_provenance':o.get('reread_provenance') or {}})
 return out
def build(result,image_sha,context_sha,max_residual=35):
 if not SHA.fullmatch(image_sha) or not SHA.fullmatch(context_sha):raise ValueError('sha_invalid')
 if result.get('schema')!='lf-structural-context-resolver/v3':raise ValueError('schema_invalid')
 residual=result.get('residual') or []
 if len(residual)>max_residual:raise ValueError('residual_budget_exceeded')
 g=result.get('geometry') or {}
 resolved=_resolved_visible_observations(result)
 out={'schema':'lf-screen-decomposer-structural-context/v3-candidate','source_image_sha256':image_sha,'context_sha256':context_sha,'role_counts':result.get('counts',{}),'anchors':g.get('anchors',{}),'header_columns':g.get('header_columns',{}),'canonical_visibility':result.get('canonical_visibility',[]),'residual_regions':[{'id':x.get('id'),'bbox':x.get('bbox'),'role':x.get('role'),'conf':x.get('conf')} for x in residual],'resolved_visible_observations':resolved,'data_lineage_policy':'ORIGINAL_EVIDENCE_IMMUTABLE_EFFECTIVE_TEXT_OVERLAY','dynamic_data_policy':'DO_NOT_CANONICAL_RECONCILE','visibility_policy':'NOT_CURRENTLY_VISIBLE_IS_NOT_MATERIAL_OMISSION','profile_contract_valid':'NOT_EVALUATED','semantic_utility':'NOT_EVALUATED'}
 out['pack_sha256']=digest(out)
 return out
