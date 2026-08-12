#!/usr/bin/env python3
from p0_visual_grader_core_v4 import *
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
   else:fs.append(finding(ctx,g,'OCR_UNCLASSIFIED_DISAGREEMENT','MEDIUM',e,{'candidate':txt,'independent_consensus':consensus,'ocr_variants':variants},'REREAD',.90,'unclassified-ocr-disagreement'))
  if e.get('classification')=='CONFIRMED' and e.get('text_group_consistency') is False:fs.append(finding(ctx,g,'TEXT_GROUPING_MISMATCH','MEDIUM',e,{'group_id':e.get('text_group_id'),'atomic_refs':e.get('source_observation_refs',[])},'REREAD',.91,'line-grouping'))
 return output(ctx,g,app,app,fs)
def j_uncertainty(candidate:dict,ctx:dict)->dict:
 g='J-UNCERTAINTY';els=candidate.get('elements',[]);app=[e['element_id'] for e in els];fs=[]
 for e in els:
  if e.get('classification')!='CONFIRMED':continue
  txt=str(e.get('visible_text') or '').strip();refs=e.get('evidence_refs') or [];variants={str(v).strip() for v in e.get('ocr_variants',[]) if str(v).strip()};disagreement=len(variants)>1 and int(e.get('ocr_agreement_count',0) or 0)<2;weak=(len(refs)==0 or e.get('redetection_status')=='NOT_REDETECTED' or disagreement or (txt and len(txt)<=3 and float(e.get('graphic_score',0) or 0)>=.55))
  if weak:fs.append(finding(ctx,g,'CONFIRMED_WITH_WEAK_EVIDENCE','HIGH',e,{'evidence_ref_count':len(refs),'ocr_variant_count':len(variants),'ocr_agreement_count':e.get('ocr_agreement_count'),'redetection_status':e.get('redetection_status'),'graphic_score':e.get('graphic_score')},'REREAD',.96,'certainty-inflation'))
 return output(ctx,g,app,app,fs)
