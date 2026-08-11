#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import run_all,canonical_sha,MATERIAL_SEVERITIES
from p0_visual_discovery_v4 import union_findings,coverage_receipt
H='a'*64
def E(txt='OK',typ='TEXT',**kw):
 d={'element_id':'E1','element_type':typ,'visible_text':txt,'classification':'CONFIRMED','confidence':.9,'semantic_role':'visible_copy','region':{'x':10,'y':10,'width':90,'height':18},'parent_id':'ROOT','evidence_refs':['adv://crop'],'ocr_variants':[txt] if txt else [],'ocr_consensus_text':txt or '','graphic_score':.05,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True};d.update(kw);return d
def C(e,**kw):
 d={'width':320,'height':120,'fresh_source_read':True,'reader_origin':'SOURCE_PIXELS','elements':[{'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':320,'height':120},'parent_id':None,'evidence_refs':['adv://full'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True},e],'coverage_map':[{'region_id':'FULL','material':True,'observed_count':2,'represented_count':2,'sweep_status':'COMPLETE'}]};d.update(kw);return d
def run(c):
 ctx={'cycle_id':'C-A','pass_id':'P-A','reader_execution_id':'R-A','source_sha256':H,'candidate_sha256':canonical_sha(c),'coverage_execution_id':'JC-A'};o=run_all(c,ctx);return union_findings(o),coverage_receipt(c,o,ctx),ctx,o
def blocked(label,c,cat=None):
 f,cov,_,_=run(c);cats={x['category'] for x in f};assert (cat in cats if cat else any(x['severity'] in MATERIAL_SEVERITIES for x in f) or not cov['coverage_pass']),(label,cats,cov);return label
def clean(label,c):
 f,cov,_,_=run(c);assert cov['coverage_pass'] and not [x for x in f if x['severity'] in MATERIAL_SEVERITIES],(label,{x['category'] for x in f});return label
def main():
 checks=[]
 checks.append(blocked('UNKNOWN_ICON_LOOKS_LIKE_LETTER',C(E('A',graphic_score=.9,ocr_variants=['A','?'])),'SHORT_TOKEN_UNCORROBORATED'))
 checks.append(clean('REAL_ISOLATED_NUMBER',C(E('7',graphic_score=.01,ocr_variants=['7'],ocr_consensus_text='7',ocr_read_count=4,ocr_empty_reads=0))))
 checks.append(clean('LEGIT_LOGO_OBJECT',C(E(None,typ='BRAND_MARK',classification='CONFIRMED'))))
 checks.append(clean('TINY_STABLE_TEXT',C(E('ok',classification='INFERRED',ocr_variants=['ok'],ocr_consensus_text='ok'))))
 checks.append(blocked('LOW_RES_UNCERTAIN_CONFIRMED',C(E('A',redetection_status='NOT_REDETECTED')),'CONFIRMED_WITH_WEAK_EVIDENCE'))
 checks.append(blocked('CONTROL_INTEGRATED_ICON',C(E('V',subcomponent_role='CHEVRON')),'CONTROL_GLYPH_AS_TEXT'))
 checks.append(clean('LONG_LEGAL_STABLE',C(E('Autorizo el tratamiento de mis datos personales conforme al aviso visible.',typ='PARAGRAPH'))))
 checks.append(clean('SHORT_BADGE_STABLE',C(E('NEW',typ='BADGE_TEXT',graphic_score=.05,ocr_variants=['NEW'],ocr_consensus_text='NEW'))))
 checks.append(blocked('ILLUSTRATION_GLYPH',C(E('I',graphic_score=.92,risk_zone='ILLUSTRATION')),'SHORT_TOKEN_UNCORROBORATED'))
 c=C(E());c['coverage_map'][0]['sweep_status']='INCOMPLETE';checks.append(blocked('PARTIAL_CROP_SWEEP',c,'OMISSION_SWEEP_INCOMPLETE'))
 checks.append(blocked('OCR_ENGINES_DISAGREE',C(E('AB',ocr_variants=['AB','A8'])),'SHORT_TOKEN_UNCORROBORATED'))
 checks.append(blocked('ARTIFICIAL_HIGH_CONFIDENCE',C(E('truth',confidence=.999,evidence_refs=[])),'HIGH_CONFIDENCE_WITHOUT_PROVENANCE'))
 checks.append(blocked('COPIED_PREVIOUS_PASS',C(E(),fresh_source_read=False,reader_origin='CLONED_PREVIOUS_PASS'),'FULL_PASS_CANDIDATE_REUSED'))
 c=C(E());_,_,ctx,outs=run(c);cov=coverage_receipt(c,outs[:-1],ctx);assert not cov['coverage_pass'];checks.append('OMITTED_GRADER_BLOCKED')
 outs=run_all(c,ctx);outs[0]['screen_regions_evaluated']=[];cov=coverage_receipt(c,outs,ctx);assert not cov['coverage_pass'];checks.append('FALSE_CLEAN_EMPTY_OUTPUT_BLOCKED')
 print(json.dumps({'gate':'PASS_V4_FORWARD_ADVERSARIAL','cases':len(checks),'critical_false_passes':0,'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
