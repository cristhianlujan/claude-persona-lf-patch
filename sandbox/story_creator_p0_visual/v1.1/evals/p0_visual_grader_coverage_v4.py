#!/usr/bin/env python3
from __future__ import annotations
import copy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import run_all,canonical_sha
from p0_visual_discovery_v4 import coverage_receipt
H='a'*64
C={'width':100,'height':100,'elements':[{'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':100,'height':100},'parent_id':None,'evidence_refs':['r'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True}]}
POLICY={'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':45.0,'text_confidence_long_min':35.0,'text_long_min_alnum':4,'object_material_area_min_px2':900,'rationale':'test fixture mirrors product policy'}
def sweep(status='COMPLETE'):
 return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':'SW1','source_sha256':H,'candidate_sha256':canonical_sha(C),'width':100,'height':100,'status':status,'fresh_source_read':True,'observations':[],'regions':[{'region_id':r,'material':True,'observed_count':0,'represented_count':0,'uncertain_count':0,'unrepresented_count':0,'sweep_status':'COMPLETE','evidence_refs':[]} for r in ('FULL','LEFT','RIGHT')],'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':500,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def base():
 ctx={'cycle_id':'C-01','pass_id':'P-01','reader_execution_id':'R1','source_sha256':H,'candidate_sha256':canonical_sha(C),'coverage_execution_id':'JC1','independent_sweep':sweep()};return ctx,run_all(C,ctx)
def blocked(label,mut):
 ctx,outs=base();mut(ctx,outs);r=coverage_receipt(C,outs,ctx);assert not r['coverage_pass'],(label,r);return label
def main():
 checks=[];ctx,outs=base();r=coverage_receipt(C,outs,ctx);assert r['coverage_pass'] and r['candidate_grader_coverage']['coverage_percent']==100 and r['independent_screen_coverage']['coverage_percent']==100;checks.append('GREEN_DUAL_COVERAGE');checks.append(blocked('MISSING_GRADER',lambda c,o:o.pop()));checks.append(blocked('ELEMENT_NOT_EVALUATED',lambda c,o:o[1].update({'evaluated_element_ids':[]})));checks.append(blocked('EMPTY_OUTPUT',lambda c,o:o[2].update({'screen_regions_evaluated':[]})));checks.append(blocked('GRADER_ERROR',lambda c,o:o[3].update({'error':'boom','status':'ERROR','coverage_complete':False})));checks.append(blocked('STALE_EXECUTION',lambda c,o:o[4].update({'reader_execution_id':'OLD'})));checks.append(blocked('DUPLICATE_EXECUTION',lambda c,o:o[5].update({'execution_id':o[4]['execution_id']})));checks.append(blocked('HASH_MISMATCH',lambda c,o:o[6].update({'candidate_sha256':'b'*64})));checks.append(blocked('MISSING_INDEPENDENT_SWEEP',lambda c,o:c.pop('independent_sweep')));checks.append(blocked('ERROR_INDEPENDENT_SWEEP',lambda c,o:c['independent_sweep'].update({'status':'ERROR','errors':['boom']})));checks.append(blocked('MISSING_OBJECT_UNIVERSE_METADATA',lambda c,o:c['independent_sweep'].pop('object_sweep')));checks.append(blocked('MISSING_MATERIALITY_POLICY',lambda c,o:c['independent_sweep'].pop('materiality_policy')));print(json.dumps({'gate':'PASS_V4_GRADER_COVERAGE','positive':1,'negative':11,'checks':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
