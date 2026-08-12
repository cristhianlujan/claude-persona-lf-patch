#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import run_all,canonical_sha
from p0_visual_discovery_v4 import union_findings
from p0_full_reader_v4 import _split_atomic_columns,_merge_same_visual_line,_lexical_corroboration
from p0_visual_grader_structure_v4 import _atomic_overmerge_groups
H='a'*64
POLICY={'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':45.0,'text_confidence_long_min':35.0,'text_long_min_alnum':4,'object_material_area_min_px2':900,'rationale':'test fixture mirrors product policy'}
PRODUCT=[ROOT/'scripts/p0_visual_graders_v4.py',ROOT/'scripts/p0_visual_discovery_v4.py',ROOT/'scripts/p0_independent_omission_sweep_v4.py',ROOT/'scripts/p0_visual_convergence_v4.py',ROOT/'scripts/run_p0_visual_quality_loop_v4.py',ROOT/'scripts/persist_p0_visual_loop_v4.py',ROOT/'scripts/p0_full_reader_v4.py',ROOT/'scripts/p0_visual_grader_structure_v4.py']
FORBIDDEN=['EL-0034','EL-0038','EL-0079','EL-0088','+51 Y','mn relacionada']
def E(txt,**kw):
 d={'element_id':'SYN-1','element_type':'TEXT','visible_text':txt,'classification':'CONFIRMED','confidence':.9,'semantic_role':'visible_copy','region':{'x':10,'y':10,'width':80,'height':20},'parent_id':'ROOT','evidence_refs':['synthetic://crop'],'ocr_variants':[txt] if txt else [],'ocr_consensus_text':txt,'graphic_score':.1,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True};d.update(kw);return d
def C(e):return {'width':300,'height':100,'fresh_source_read':True,'reader_origin':'SOURCE_PIXELS','elements':[{'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':300,'height':100},'parent_id':None,'evidence_refs':['synthetic://full'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True},e]}
def S(c):return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':'SW-R','source_sha256':H,'candidate_sha256':canonical_sha(c),'width':300,'height':100,'status':'COMPLETE','fresh_source_read':True,'observations':[],'regions':[{'region_id':r,'material':True,'observed_count':0,'represented_count':0,'uncertain_count':0,'unrepresented_count':0,'sweep_status':'COMPLETE','evidence_refs':[]} for r in ('FULL','LEFT','RIGHT')],'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':500,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def cats(c):
 ctx={'cycle_id':'C-R','pass_id':'P-R','reader_execution_id':'R-R','source_sha256':H,'candidate_sha256':canonical_sha(c),'coverage_execution_id':'JC-R','independent_sweep':S(c)};return {f['category'] for f in union_findings(run_all(c,ctx))}
def expect(label,cat,c):x=cats(c);assert cat in x,(label,cat,x);return label
def _fake_ocr_data(words:list[tuple[str,int,int,int,int]])->dict:
 n=len(words);return {'left':[x[1] for x in words],'top':[x[2] for x in words],'width':[x[3] for x in words],'height':[x[4] for x in words]}
def _items(words:list[tuple[str,int,int,int,int]]):return [(i,w[0],96.0) for i,w in enumerate(words)]
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
 stable=cats(C(E('51',ocr_consensus_text='51',ocr_variants=['51'],ocr_read_count=4,ocr_empty_reads=0)));assert 'SHORT_TOKEN_UNCORROBORATED' not in stable;checks.append('RESTORE_REAL_SHORT_NUMBER')
 words=[('Celular',10,10,50,12),('Correo',310,10,50,12),('electrónico',365,10,80,12)];clusters=_split_atomic_columns(_items(words),_fake_ocr_data(words));assert len(clusters)==2;checks.append('ATOMIC_SPLIT_SIDE_BY_SIDE_LABELS')
 words=[('Número',10,10,50,12),('de',65,10,16,12),('documento',86,10,78,12)];clusters=_split_atomic_columns(_items(words),_fake_ocr_data(words));assert len(clusters)==1;checks.append('RESTORE_MULTIWORD_LABEL_GROUPING')
 words=[('tu',10,10,38,28),('deuda',62,6,122,33)];data=_fake_ocr_data(words);groups=_merge_same_visual_line([[_items(words)[0]],[_items(words)[1]]],data);assert len(groups)==1;checks.append('RESTORE_SAME_BASELINE_PHRASE')
 words=[('1',10,10,16,28),('Consulta',65,15,68,13)];data=_fake_ocr_data(words);groups=_merge_same_visual_line([[_items(words)[0]],[_items(words)[1]]],data);assert len(groups)==2;checks.append('NO_STEP_NUMBER_OVERMERGE')
 assert _lexical_corroboration('tu',['tu','tu deuda','tu deuda'])==3;checks.append('RESTORE_SHORT_LEXICAL_TOKEN_CORROBORATION')
 sw={'observations':[{'observation_id':'O1','kind':'TEXT','material':True,'match_status':'REPRESENTED','matched_element_id':'E-MERGED','text':'Celular','region':{'x':10,'y':10,'width':50,'height':12}},{'observation_id':'O2','kind':'TEXT','material':True,'match_status':'REPRESENTED','matched_element_id':'E-MERGED','text':'Correo electrónico','region':{'x':310,'y':10,'width':130,'height':12}}]};assert 'E-MERGED' in _atomic_overmerge_groups(sw);checks.append('BLOCK_OVERMERGED_COVERAGE')
 sw={'observations':[{'observation_id':'O1','kind':'TEXT','material':True,'match_status':'REPRESENTED','matched_element_id':'E-PHRASE','text':'Número','region':{'x':10,'y':10,'width':50,'height':12}},{'observation_id':'O2','kind':'TEXT','material':True,'match_status':'REPRESENTED','matched_element_id':'E-PHRASE','text':'documento','region':{'x':66,'y':10,'width':78,'height':12}}]};assert 'E-PHRASE' not in _atomic_overmerge_groups(sw);checks.append('NO_FALSE_OVERMERGE_WITHIN_LABEL')
 out={'gate':'PASS_V4_HUMAN_FINDINGS_AS_REGRESSIONS','checks':len(checks),'known_classes_detected':9,'unseen_holdout_detected':1,'restores':5,'atomic_segmentation_defended':True,'results':checks};print(json.dumps(out,sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
