#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import run_all,canonical_sha
from p0_visual_discovery_v4 import union_findings,coverage_receipt
H='a'*64
POLICY={'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':45.0,'text_confidence_long_min':35.0,'text_long_min_alnum':4,'object_material_area_min_px2':900,'rationale':'test fixture mirrors product policy'}

def E(i='E1',typ='TEXT',txt='OK',**kw):
 d={'element_id':i,'element_type':typ,'visible_text':txt,'classification':'CONFIRMED','confidence':.9,'region':{'x':10,'y':10,'width':50,'height':20},'parent_id':'ROOT','evidence_refs':['crop://'+i],'ocr_variants':[txt] if txt else [],'ocr_consensus_text':txt or '','graphic_score':0.1,'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True};d.update(kw);return d
def C(e):return {'width':500,'height':300,'elements':[{'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1.0,'region':{'x':0,'y':0,'width':500,'height':300},'parent_id':None,'evidence_refs':['region://root'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True},e]}
def S(c,status='COMPLETE'):
 return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':'SW-UNIT','source_sha256':H,'candidate_sha256':canonical_sha(c),'width':c['width'],'height':c['height'],'status':status,'fresh_source_read':True,'observations':[],'regions':[{'region_id':r,'material':True,'observed_count':0,'represented_count':0,'uncertain_count':0,'unrepresented_count':0,'sweep_status':'COMPLETE','evidence_refs':[]} for r in ('FULL','LEFT','RIGHT')],'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':500,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def run(c,passid='P-01'):
 ctx={'cycle_id':'C-01','pass_id':passid,'reader_execution_id':'R-'+passid,'source_sha256':H,'candidate_sha256':canonical_sha(c),'coverage_execution_id':'JC-'+passid};ctx['independent_sweep']=S(c);outs=run_all(c,ctx);return union_findings(outs),coverage_receipt(c,outs,ctx)
def cats(c):return {f['category'] for f in run(c)[0]}
def has(name,cat,c):cs=cats(c);assert cat in cs,(name,cat,cs);return name
def no(name,cat,c):cs=cats(c);assert cat not in cs,(name,cat,cs);return name
def main():
 checks=[has('icon_to_text','SHORT_TOKEN_UNCORROBORATED',C(E(txt='7',graphic_score=.85,ocr_variants=['7','?']))),has('control_glyph','CONTROL_GLYPH_AS_TEXT',C(E(txt='Y',subcomponent_role='CHEVRON'))),has('prefix_garbage','OCR_PREFIX_GARBAGE',C(E(txt='mn relacionada',ocr_consensus_text='relacionada'))),has('diacritic','DIACRITIC_MISMATCH',C(E(txt='informacion',ocr_consensus_text='información'))),has('grouping','TEXT_GROUPING_MISMATCH',C(E(text_group_consistency=False,text_group_id='G1'))),has('certainty','CONFIRMED_WITH_WEAK_EVIDENCE',C(E(txt='A',evidence_refs=[],ocr_variants=['A','?']))),has('unclassified_long_disagreement','OCR_UNCLASSIFIED_DISAGREEMENT',C(E(txt='TRANSFERENCIA CONFIRMADA',ocr_consensus_text='TRANSFERENCIA RECHAZADA',ocr_variants=['TRANSFERENCIA CONFIRMADA','TRANSFERENCIA RECHAZADA'])))]
 c=C(E());c['elements'][1]['style']={'font_family':'Inter'};c['elements'][1]['style_provenance']={};checks.append(has('style_exact','UNSUPPORTED_EXACT_STYLE_CLAIM',c))
 checks += [no('real_short_number_restore','SHORT_TOKEN_UNCORROBORATED',C(E(txt='51',graphic_score=.05,ocr_variants=['51'],ocr_consensus_text='51'))),no('real_diacritic_restore','DIACRITIC_MISMATCH',C(E(txt='información',ocr_consensus_text='información'))),no('declared_style_restore','UNSUPPORTED_EXACT_STYLE_CLAIM',C(E(style={'font_family':'Inter'},style_provenance={'font_family':'DECLARED'})))]
 _,cov=run(C(E()));assert cov['coverage_pass'] and cov['coverage_percent']==100.0 and cov['candidate_grader_coverage']['complete'] and cov['independent_screen_coverage']['complete'];checks.append('dual_coverage_green_restore');print(json.dumps({'gate':'PASS_V4_GRADERS','checks':len(checks),'known_failure_classes':8,'restores':4,'coverage_pass':True,'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
