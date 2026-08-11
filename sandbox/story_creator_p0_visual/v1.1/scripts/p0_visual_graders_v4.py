#!/usr/bin/env python3
"""Independent deterministic V4 visual graders. Productive logic detects classes, never known IDs/literals."""
from __future__ import annotations
import hashlib,json,unicodedata
from typing import Any,Callable
GRADERS=("J-TEXT","J-OBJECT","J-COMPLETE","J-GEOMETRY","J-STRUCTURE","J-STYLE","J-SEMANTIC","J-UNCERTAINTY","J-SKEPTIC")
TEXT_TYPES={"TEXT","LABEL","HEADING","LINK","BUTTON_TEXT","BADGE_TEXT","INPUT_TEXT"};MATERIAL_SEVERITIES={"CRITICAL","HIGH","MEDIUM"}
def canonical_sha(obj:Any)->str:return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
def strip_marks(s:str)->str:return ''.join(c for c in unicodedata.normalize('NFD',s) if unicodedata.category(c)!='Mn')
def common_prefix(a:str,b:str)->str:
 out=[]
 for x,y in zip(a,b):
  if x!=y:break
  out.append(x)
 return ''.join(out)
def bbox(e:dict)->dict:return e.get('region') or {'x':0,'y':0,'width':0,'height':0}
def finding(ctx:dict,grader:str,category:str,severity:str,element:dict|None,evidence:Any,actionability:str='REREAD',confidence:float=.9,root:str|None=None,claim:Any=None)->dict:
 eid=(element or {}).get('element_id');rid=bbox(element or {});seed=f"{ctx['cycle_id']}|{ctx['pass_id']}|{grader}|{category}|{eid}|{canonical_sha(evidence)}"
 return {'schema_version':'p0-visual-finding-v4/v1','finding_id':'F-'+hashlib.sha256(seed.encode()).hexdigest()[:16],'cycle_id':ctx['cycle_id'],'pass_id':ctx['pass_id'],'grader_id':grader,'category':category,'severity':severity,'element_id':eid,'region':{k:int(rid.get(k,0) or 0) for k in ('x','y','width','height')},'candidate_claim':claim if claim is not None else (element or {}).get('visible_text'),'observed_evidence':evidence,'evidence_refs':list((element or {}).get('evidence_refs') or []),'confidence':float(max(0,min(1,confidence))),'actionability':actionability,'root_cause_candidate':root,'status':'OPEN'}
def output(ctx:dict,grader:str,applicable:list[str],evaluated:list[str],findings:list[dict],regions:list[str]|None=None,error:str|None=None)->dict:
 return {'schema_version':'p0-grader-output-v4/v1','execution_id':ctx['grader_execution_id'],'reader_execution_id':ctx['reader_execution_id'],'cycle_id':ctx['cycle_id'],'pass_id':ctx['pass_id'],'grader_id':grader,'source_sha256':ctx['source_sha256'],'candidate_sha256':ctx['candidate_sha256'],'applicable_element_ids':applicable,'evaluated_element_ids':evaluated,'screen_regions_evaluated':regions or ['FULL'],'findings':findings,'coverage_complete':error is None and set(evaluated)==set(applicable),'status':'ERROR' if error else ('BLOCKED' if any(f['severity'] in MATERIAL_SEVERITIES for f in findings) else 'PASS'),'error':error}
def applies_text(e:dict)->bool:return bool(e.get('visible_text')) or e.get('element_type') in TEXT_TYPES
def j_text(candidate:dict,ctx:dict)->dict:
 g='J-TEXT';els=candidate.get('elements',[]);app=[e['element_id'] for e in els if applies_text(e)];fs=[]
 for e in els:
  if e['element_id'] not in app:continue
  txt=str(e.get('visible_text') or '').strip();variants=[str(x).strip() for x in e.get('ocr_variants',[]) if str(x).strip()];consensus=str(e.get('ocr_consensus_text') or '').strip();graphic=float(e.get('graphic_score',0) or 0);read_count=int(e.get('ocr_read_count',len(e.get('ocr_variants',[]) or [])) or 0);empty_reads=int(e.get('ocr_empty_reads',0) or 0)
  if txt and len(txt)<=3 and e.get('classification')=='CONFIRMED' and (graphic>=.60 or len(set(variants))>1 or (read_count>=3 and empty_reads/read_count>=.5)):fs.append(finding(ctx,g,'SHORT_TOKEN_UNCORROBORATED','HIGH',e,{'text':txt,'graphic_score':graphic,'ocr_variants':variants,'ocr_read_count':read_count,'ocr_empty_reads':empty_reads},'REREAD',.94,'short-token-evidence-policy'))
  if txt and consensus and txt!=consensus:
   cp=common_prefix(txt,consensus);tail_txt=txt[len(cp):].strip();tail_cons=consensus[len(cp):].strip()
   if e.get('semantic_role')=='control_visible_text' and len(cp.strip())>=2 and 0<len(tail_txt)<=3 and 0<len(tail_cons)<=3:fs.append(finding(ctx,g,'CONTROL_SUFFIX_GLYPH_CONFLICT','HIGH',e,{'candidate':txt,'independent_consensus':consensus,'stable_prefix':cp},'REREAD',.95,'control-adornment-text-conflict'))
   if strip_marks(txt).casefold()==strip_marks(consensus).casefold():
    if strip_marks(txt)!=txt or strip_marks(consensus)!=consensus:fs.append(finding(ctx,g,'DIACRITIC_MISMATCH','MEDIUM',e,{'candidate':txt,'independent_consensus':consensus},'AUTO_REMEDIATE',.96,'diacritic-preservation'))
    elif txt.casefold()==consensus.casefold():fs.append(finding(ctx,g,'OCR_CASE_MISMATCH','MEDIUM',e,{'candidate':txt,'independent_consensus':consensus},'REREAD',.91,'case-preservation'))
   elif consensus in txt and len(txt)-len(consensus)<=4:
    cat='OCR_PREFIX_GARBAGE' if txt.endswith(consensus) else 'OCR_SUFFIX_GARBAGE' if txt.startswith(consensus) else 'OCR_EMBEDDED_GARBAGE';fs.append(finding(ctx,g,cat,'HIGH',e,{'candidate':txt,'independent_consensus':consensus},'AUTO_REMEDIATE',.94,'unsupported-extra-token'))
   elif txt in consensus and len(consensus)-len(txt)<=4:fs.append(finding(ctx,g,'OCR_SUFFIX_OR_PREFIX_OMISSION','MEDIUM',e,{'candidate':txt,'independent_consensus':consensus},'REREAD',.90,'incomplete-text'))
   elif len(txt)<=3 or len(consensus)<=3:fs.append(finding(ctx,g,'OCR_SHORT_TOKEN_DISAGREEMENT','HIGH',e,{'candidate':txt,'independent_consensus':consensus},'REREAD',.93,'short-token-disagreement'))
  if e.get('text_group_consistency') is False:fs.append(finding(ctx,g,'TEXT_GROUPING_MISMATCH','MEDIUM',e,{'group_id':e.get('text_group_id'),'atomic_refs':e.get('source_observation_refs',[])},'REREAD',.91,'line-grouping'))
 return output(ctx,g,app,app,fs)
def j_object(candidate:dict,ctx:dict)->dict:
 g='J-OBJECT';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[]
 for e in els:
  typ=e.get('element_type');txt=str(e.get('visible_text') or '').strip();graphic=float(e.get('graphic_score',0) or 0);role=e.get('subcomponent_role')
  if typ in TEXT_TYPES and graphic>=.72 and len(txt)<=3:fs.append(finding(ctx,g,'OBJECT_TEXT_GRAPHIC_CONFLICT','HIGH',e,{'element_type':typ,'graphic_score':graphic,'text':txt},'REREAD',.95,'object-classification'))
  if role in {'CHEVRON','ICON','GLYPH','SECURITY_ICON'} and typ in TEXT_TYPES:fs.append(finding(ctx,g,'CONTROL_GLYPH_AS_TEXT','HIGH',e,{'subcomponent_role':role,'element_type':typ},'AUTO_REMEDIATE',.97,'control-subcomponent'))
  if typ=='TEXT' and e.get('brand_mark_score',0)>=.75:fs.append(finding(ctx,g,'BRAND_MARK_AS_TEXT','HIGH',e,{'brand_mark_score':e.get('brand_mark_score')},'REREAD',.92,'brand-object'))
 return output(ctx,g,app,app,fs)
def j_complete(candidate:dict,ctx:dict)->dict:
 g='J-COMPLETE';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];regions=[]
 for r in candidate.get('coverage_map',[]) or [{'region_id':'FULL','material':True,'observed_count':len(els),'represented_count':len(els)}]:
  if not r.get('material',True):continue
  regions.append(str(r.get('region_id','UNKNOWN')))
  if int(r.get('represented_count',0))<int(r.get('observed_count',0)):fs.append(finding(ctx,g,'MATERIAL_OMISSION','HIGH',None,{'region_id':r.get('region_id'),'observed_count':r.get('observed_count'),'represented_count':r.get('represented_count')},'REREAD',.95,'omission-sweep'))
  if r.get('sweep_status') in {'INCOMPLETE','ERROR'}:fs.append(finding(ctx,g,'OMISSION_SWEEP_INCOMPLETE','HIGH',None,{'region_id':r.get('region_id'),'sweep_status':r.get('sweep_status')},'BLOCK',.99,'coverage-gap'))
 return output(ctx,g,app,app,fs,regions or ['FULL'])
def inside(child:dict,parent:dict,tol:int=12)->bool:
 c=bbox(child);p=bbox(parent);return c['x']>=p['x']-tol and c['y']>=p['y']-tol and c['x']+c['width']<=p['x']+p['width']+tol and c['y']+c['height']<=p['y']+p['height']+tol
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
def j_style(candidate:dict,ctx:dict)->dict:
 g='J-STYLE';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];exact={'hex','font_family','font_size_px','radius_px','shadow_css'}
 for e in els:
  for prop,val in (e.get('style') or {}).items():
   if prop in exact and val not in (None,'NOT_OBSERVABLE'):
    prov=(e.get('style_provenance') or {}).get(prop)
    if prov not in {'DECLARED','RECONCILED','OBSERVED_STRONG'}:fs.append(finding(ctx,g,'UNSUPPORTED_EXACT_STYLE_CLAIM','MEDIUM',e,{'property':prop,'value':val,'provenance':prov},'AUTO_REMEDIATE',.94,'style-provenance'))
 return output(ctx,g,app,app,fs)
def j_semantic(candidate:dict,ctx:dict)->dict:
 g='J-SEMANTIC';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];compatible={'LINK':{'LINK','TEXT'},'CTA':{'BUTTON'},'CONSENT':{'CHECKBOX','TEXT','LABEL'},'SECURITY_INDICATOR':{'ICON','BADGE','TEXT'},'INPUT_LABEL':{'LABEL','TEXT'}}
 for e in els:
  role=e.get('semantic_role');typ=e.get('element_type')
  if role in compatible and typ not in compatible[role]:fs.append(finding(ctx,g,'SEMANTIC_TYPE_CONFLICT','MEDIUM',e,{'semantic_role':role,'element_type':typ},'REREAD',.90,'semantic-visual-coherence'))
  if e.get('business_rule_claim') and not e.get('business_rule_visible_evidence'):fs.append(finding(ctx,g,'NONVISUAL_BUSINESS_RULE_INFERENCE','HIGH',e,{'claim':e.get('business_rule_claim')},'AUTO_REMEDIATE',.98,'semantic-overreach'))
 return output(ctx,g,app,app,fs)
def j_uncertainty(candidate:dict,ctx:dict)->dict:
 g='J-UNCERTAINTY';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[]
 for e in els:
  if e.get('classification')!='CONFIRMED':continue
  txt=str(e.get('visible_text') or '').strip();refs=e.get('evidence_refs') or [];variants={str(v).strip() for v in e.get('ocr_variants',[]) if str(v).strip()};weak=(len(refs)==0 or e.get('redetection_status')=='NOT_REDETECTED' or len(variants)>1 or (txt and len(txt)<=3 and float(e.get('graphic_score',0) or 0)>=.55))
  if weak:fs.append(finding(ctx,g,'CONFIRMED_WITH_WEAK_EVIDENCE','HIGH',e,{'evidence_ref_count':len(refs),'ocr_variant_count':len(variants),'redetection_status':e.get('redetection_status'),'graphic_score':e.get('graphic_score')},'REREAD',.96,'certainty-inflation'))
 return output(ctx,g,app,app,fs)
def j_skeptic(candidate:dict,ctx:dict)->dict:
 g='J-SKEPTIC';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];prev=candidate.get('previous_full_pass_candidate_sha256')
 if candidate.get('fresh_source_read') is False or candidate.get('reader_origin')=='CLONED_PREVIOUS_PASS' or (prev and prev==ctx['candidate_sha256']):fs.append(finding(ctx,g,'FULL_PASS_CANDIDATE_REUSED','HIGH',None,{'previous_candidate_sha256':prev,'candidate_sha256':ctx['candidate_sha256'],'fresh_source_read':candidate.get('fresh_source_read'),'reader_origin':candidate.get('reader_origin')},'BLOCK',.99,'context-reset-failure'))
 for e in els:
  if float(e.get('confidence',0) or 0)>=.97 and e.get('classification')=='CONFIRMED' and len(e.get('evidence_refs') or [])<1:fs.append(finding(ctx,g,'HIGH_CONFIDENCE_WITHOUT_PROVENANCE','HIGH',e,{'confidence':e.get('confidence')},'REREAD',.98,'skeptical-provenance'))
  if e.get('risk_zone') in {'DENSE','LEGAL','BRANDING','ILLUSTRATION'} and not e.get('independent_redetection',False):fs.append(finding(ctx,g,'HIGH_RISK_ZONE_NOT_REDETECTED','MEDIUM',e,{'risk_zone':e.get('risk_zone')},'REREAD',.91,'skeptical-redetection'))
 return output(ctx,g,app,app,fs)
RUNNERS:dict[str,Callable[[dict,dict],dict]]={'J-TEXT':j_text,'J-OBJECT':j_object,'J-COMPLETE':j_complete,'J-GEOMETRY':j_geometry,'J-STRUCTURE':j_structure,'J-STYLE':j_style,'J-SEMANTIC':j_semantic,'J-UNCERTAINTY':j_uncertainty,'J-SKEPTIC':j_skeptic}
def run_grader(grader_id:str,candidate:dict,ctx:dict)->dict:
 if grader_id not in RUNNERS:raise ValueError(f'unknown grader {grader_id}')
 local=dict(ctx);local['grader_execution_id']=ctx.get('grader_execution_id') or f"{grader_id}-{ctx['pass_id']}";return RUNNERS[grader_id](candidate,local)
def run_all(candidate:dict,ctx:dict)->list[dict]:
 outs=[]
 for idx,g in enumerate(GRADERS,1):
  local=dict(ctx);local['grader_execution_id']=f"{ctx['pass_id']}-{g}-{idx:02d}";outs.append(run_grader(g,candidate,local))
 return outs
