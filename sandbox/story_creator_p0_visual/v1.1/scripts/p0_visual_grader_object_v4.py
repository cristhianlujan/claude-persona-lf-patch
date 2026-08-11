#!/usr/bin/env python3
from p0_visual_grader_core_v4 import *
def j_object(candidate:dict,ctx:dict)->dict:
 g='J-OBJECT';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[]
 for e in els:
  typ=e.get('element_type');txt=str(e.get('visible_text') or '').strip();graphic=float(e.get('graphic_score',0) or 0);role=e.get('subcomponent_role')
  if typ in TEXT_TYPES and graphic>=.72 and len(txt)<=3:fs.append(finding(ctx,g,'OBJECT_TEXT_GRAPHIC_CONFLICT','HIGH',e,{'element_type':typ,'graphic_score':graphic,'text':txt},'REREAD',.95,'object-classification'))
  if role in {'CHEVRON','ICON','GLYPH','SECURITY_ICON'} and typ in TEXT_TYPES:fs.append(finding(ctx,g,'CONTROL_GLYPH_AS_TEXT','HIGH',e,{'subcomponent_role':role,'element_type':typ},'AUTO_REMEDIATE',.97,'control-subcomponent'))
  if typ=='TEXT' and e.get('brand_mark_score',0)>=.75:fs.append(finding(ctx,g,'BRAND_MARK_AS_TEXT','HIGH',e,{'brand_mark_score':e.get('brand_mark_score')},'REREAD',.92,'brand-object'))
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
def j_skeptic(candidate:dict,ctx:dict)->dict:
 g='J-SKEPTIC';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[];prev=candidate.get('previous_full_pass_candidate_sha256')
 if candidate.get('fresh_source_read') is False or candidate.get('reader_origin')=='CLONED_PREVIOUS_PASS' or (prev and prev==ctx['candidate_sha256']):fs.append(finding(ctx,g,'FULL_PASS_CANDIDATE_REUSED','HIGH',None,{'previous_candidate_sha256':prev,'candidate_sha256':ctx['candidate_sha256'],'fresh_source_read':candidate.get('fresh_source_read'),'reader_origin':candidate.get('reader_origin')},'BLOCK',.99,'context-reset-failure'))
 for e in els:
  if float(e.get('confidence',0) or 0)>=.97 and e.get('classification')=='CONFIRMED' and len(e.get('evidence_refs') or [])<1:fs.append(finding(ctx,g,'HIGH_CONFIDENCE_WITHOUT_PROVENANCE','HIGH',e,{'confidence':e.get('confidence')},'REREAD',.98,'skeptical-provenance'))
  if e.get('classification')=='CONFIRMED' and e.get('risk_zone') in {'DENSE','LEGAL','BRANDING','ILLUSTRATION'} and not e.get('independent_redetection',False):fs.append(finding(ctx,g,'HIGH_RISK_ZONE_NOT_REDETECTED','MEDIUM',e,{'risk_zone':e.get('risk_zone')},'REREAD',.91,'skeptical-redetection'))
 return output(ctx,g,app,app,fs)
