#!/usr/bin/env python3
import hashlib,json,re
SHA=re.compile(r'^[0-9a-f]{64}$')
def digest(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def build(result,image_sha,context_sha,max_residual=35):
 if not SHA.fullmatch(image_sha) or not SHA.fullmatch(context_sha):raise ValueError('sha_invalid')
 if result.get('schema')!='lf-structural-context-resolver/v3':raise ValueError('schema_invalid')
 residual=result.get('residual') or []
 if len(residual)>max_residual:raise ValueError('residual_budget_exceeded')
 g=result.get('geometry') or {}
 out={'schema':'lf-screen-decomposer-structural-context/v3-candidate','source_image_sha256':image_sha,'context_sha256':context_sha,'role_counts':result.get('counts',{}),'anchors':g.get('anchors',{}),'header_columns':g.get('header_columns',{}),'canonical_visibility':result.get('canonical_visibility',[]),'residual_regions':[{'id':x.get('id'),'bbox':x.get('bbox'),'role':x.get('role'),'conf':x.get('conf')} for x in residual],'dynamic_data_policy':'DO_NOT_CANONICAL_RECONCILE','visibility_policy':'NOT_CURRENTLY_VISIBLE_IS_NOT_MATERIAL_OMISSION','profile_contract_valid':'NOT_EVALUATED','semantic_utility':'NOT_EVALUATED'}
 out['pack_sha256']=digest(out)
 return out
