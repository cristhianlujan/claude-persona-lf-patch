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
def S(c):return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':'SW-R','source_sha256':H,'candidate_sha256':canonical_sha(c),'width':300,'height':100,'status':'COMPLETE','fresh_source_read':True,'observations':[],'regions':[{'region_id':r,'material':True,'observed_count':0,'represented_count':0,'uncertain_count':0,'unrepresented_count':0,'sweep_status':'COMPLETE','evidence_refs':[]} for r in ('FULL','LEFT','RIGHT')],'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':500,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def cats(c):
 ctx={'cycle_id':'C-R','pass_id':'P-R','reader_execution_id':'R-R','source_sha256':H,'candidate_sha256':canonical_sha(c),'coverage_execution_id':'JC-R','independent_sweep':S(c)};return {f['category'] for f in union_findings(run_all(c,ctx))}
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
 stable=cats(C(E('51',ocr_consensus_text='51',ocr_variants=['51'],ocr_read_count=4,ocr_empty_reads=0)));assert 'SHORT_TOKEN_UNCORROBORATED' not in stable and 'SHORT_TEXT_WITHOUT_MATERIAL_SUPPORT' not in stable;checks.append('RESTORE_REAL_SHORT_NUMBER')
 print(json.dumps({'gate':'PASS_V4_HUMAN_FINDINGS_AS_REGRESSIONS','checks':len(checks),'known_classes_detected':10,'unseen_holdout_detected':1,'restores':1,'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())