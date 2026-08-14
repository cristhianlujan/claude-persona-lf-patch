#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import run_all,canonical_sha
from p0_visual_discovery_v4 import union_findings
H='a'*64
POLICY={'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':45.0,'text_confidence_long_min':35.0,'text_long_min_alnum':4,'object_material_area_min_px2':900,'rationale':'test fixture mirrors product policy'}
PRODUCT=[ROOT/'scripts/p0_visual_graders_v4.py',ROOT/'scripts/p0_visual_discovery_v4.py',ROOT/'scripts/p0_independent_omission_sweep_v4.py',ROOT/'scripts/p0_visual_convergence_v4.py',ROOT/'scripts/run_p0_visual_quality_loop_v4.py',ROOT/'scripts/persist_p0_visual_loop_v4.py']
FORBIDDEN=['EL-0034','EL-0038','EL-0079','EL-0088','+51 Y','mn relacionada']
def E(txt,**kw):
 d={'element_id':'SYN-1','element_type':'TEXT','visible_text':txt,'classification':'CONFIRMED','confidence':.9,'semantic_role':'visible_copy','region':{'x':10,'y':10,'width':80,'height':20},'parent_id':'ROOT','evidence_refs':['synthetic://crop'],'ocr_variants':[txt] if txt else [],'ocr_consensus_text':txt,'graphic_score':.1,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True};d.update(kw);return d
def C(e):return {'width':300,'height':100,'fresh_source_read':True,'reader_origin':'SOURCE_PIXELS','elements':[{'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':300,'height':100},'parent_id':None,'evidence_refs':['synthetic://full'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True},e]}
def S(c,observations=None):
 observations=list(observations or []);regions=[]
 for rid in ('FULL','LEFT','RIGHT'):
  items=[o for o in observations if o.get('material') is True and (rid=='FULL' or ((o.get('region') or {}).get('x',0)+(o.get('region') or {}).get('width',0)/2<150)==(rid=='LEFT'))]
  represented=sum(o.get('match_status')=='REPRESENTED' for o in items);uncertain=sum(o.get('match_status')=='UNCERTAIN' for o in items);unrepresented=sum(o.get('match_status')=='UNREPRESENTED' for o in items)
  regions.append({'region_id':rid,'material':True,'observed_count':len(items),'represented_count':represented,'uncertain_count':uncertain,'unrepresented_count':unrepresented,'sweep_status':'COMPLETE' if uncertain==0 else 'INCOMPLETE','evidence_refs':sorted({r for o in items for r in o.get('evidence_refs',[])})})
 return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':'SW-R','source_sha256':H,'candidate_sha256':canonical_sha(c),'width':300,'height':100,'status':'COMPLETE','fresh_source_read':True,'observations':observations,'regions':regions,'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':500,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[o['observation_id'] for o in observations if o.get('material') is True and o.get('match_status')=='UNREPRESENTED'],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def cats(c,sweep=None):
 ctx={'cycle_id':'C-R','pass_id':'P-R','reader_execution_id':'R-R','source_sha256':H,'candidate_sha256':canonical_sha(c),'coverage_execution_id':'JC-R','independent_sweep':sweep or S(c)};return {f['category'] for f in union_findings(run_all(c,ctx))}
def expect(label,cat,c):x=cats(c);assert cat in x,(label,cat,x);return label
def main():
 checks=[]
 for p in PRODUCT:
  text=p.read_text(encoding='utf-8')
  for token in FORBIDDEN:assert token not in text,(p.name,token)
 checks.append('NO_KNOWN_ID_OR_LITERAL_HARDCODE_IN_PRODUCT')
 checks.append(expect('icon_like_short','SHORT_TOKEN_UNCORROBORATED',C(E('42',ocr_variants=['(2'],ocr_read_count=4,ocr_empty_reads=3))))
 checks.append(expect('decorated_control','CONTROL_SUFFIX_GLYPH_CONFLICT',C(E('+34 Z',ocr_consensus_text='+34 vv',semantic_role='control_visible_text'))))
 checks.append(expect('prefix_noise','OCR_PREFIX_GARBAGE',C(E('xx relacionada',ocr_consensus_text='relacionada'))))
 checks.append(expect('diacritic_loss','DIACRITIC_MISMATCH',C(E('informacion',ocr_consensus_text='información'))))
 checks.append(expect('isolated_symbol','OCR_SHORT_TOKEN_DISAGREEMENT',C(E('&',ocr_consensus_text='a'))))
 checks.append(expect('certainty_inflation','CONFIRMED_WITH_WEAK_EVIDENCE',C(E('Q',evidence_refs=[],ocr_variants=['Q','?']))))
 checks.append(expect('grouping','TEXT_GROUPING_MISMATCH',C(E('texto partido',text_group_consistency=False,text_group_id='G-SYN'))))
 checks.append(expect('unclassified_disagreement','OCR_UNCLASSIFIED_DISAGREEMENT',C(E('DOCUMENTO APROBADO',ocr_consensus_text='DOCUMENTO RECHAZADO',ocr_variants=['DOCUMENTO APROBADO','DOCUMENTO RECHAZADO']))))
 checks.append(expect('unseen_case_mismatch','OCR_CASE_MISMATCH',C(E('x',ocr_consensus_text='X'))))
 checks.append(expect('inferred_short_same_family_only','SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT',C(E('10',classification='INFERRED',independent_redetection=False,ocr_variants=['10','10'],ocr_read_count=3,ocr_empty_reads=1,ocr_agreement_count=2))))
 confirmed=C(E('51',ocr_consensus_text='51',ocr_variants=['51'],ocr_read_count=4,ocr_empty_reads=0));stable=cats(confirmed);assert 'SHORT_TOKEN_UNCORROBORATED' not in stable and 'SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT' not in stable;checks.append('RESTORE_CONFIRMED_SHORT_NUMBER')
 inferred=C(E('51',classification='INFERRED',independent_redetection=False,ocr_consensus_text='',ocr_variants=['51','51'],ocr_read_count=3,ocr_empty_reads=1,ocr_agreement_count=2));obs={'observation_id':'OBS-SHORT-51','kind':'TEXT','text':'51','classification':'CONFIRMED','confidence':.96,'region':{'x':10,'y':10,'width':80,'height':20},'material':True,'match_status':'REPRESENTED','matched_element_id':'SYN-1','match_score':1.0,'evidence_refs':['synthetic://source']};supported=cats(inferred,S(inferred,[obs]));assert 'SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT' not in supported,supported;checks.append('RESTORE_INFERRED_SHORT_NUMBER_WITH_MATERIAL_SUPPORT')
 print(json.dumps({'gate':'PASS_V4_HUMAN_FINDINGS_AS_REGRESSIONS','checks':len(checks),'known_classes_detected':10,'unseen_holdout_detected':1,'restores':2,'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())