#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import run_all,canonical_sha
from p0_visual_discovery_v4 import coverage_receipt
H='a'*64
C={'width':100,'height':100,'elements':[{'element_id':'ROOT','element_type':'CONTAINER','visible_text':None,'classification':'CONFIRMED','confidence':1,'region':{'x':0,'y':0,'width':100,'height':100},'parent_id':None,'evidence_refs':['r'],'bbox_reproducible':True,'style':{},'style_provenance':{},'independent_redetection':True}],'coverage_map':[{'region_id':'FULL','material':True,'observed_count':1,'represented_count':1,'sweep_status':'COMPLETE'}]}
def base():
 ctx={'cycle_id':'C-01','pass_id':'P-01','reader_execution_id':'R1','source_sha256':H,'candidate_sha256':canonical_sha(C),'coverage_execution_id':'JC1'};return ctx,run_all(C,ctx)
def blocked(label,mut):
 ctx,outs=base();mut(ctx,outs);r=coverage_receipt(C,outs,ctx);assert not r['coverage_pass'],(label,r);return label
def main():
 checks=[];ctx,outs=base();r=coverage_receipt(C,outs,ctx);assert r['coverage_pass'];checks.append('GREEN');checks.append(blocked('MISSING_GRADER',lambda c,o:o.pop()));checks.append(blocked('ELEMENT_NOT_EVALUATED',lambda c,o:o[1].update({'evaluated_element_ids':[]})));checks.append(blocked('EMPTY_OUTPUT',lambda c,o:o[2].update({'screen_regions_evaluated':[]})));checks.append(blocked('GRADER_ERROR',lambda c,o:o[3].update({'error':'boom','status':'ERROR','coverage_complete':False})));checks.append(blocked('STALE_EXECUTION',lambda c,o:o[4].update({'reader_execution_id':'OLD'})));checks.append(blocked('DUPLICATE_EXECUTION',lambda c,o:o[5].update({'execution_id':o[4]['execution_id']})));checks.append(blocked('HASH_MISMATCH',lambda c,o:o[6].update({'candidate_sha256':'b'*64})));print(json.dumps({'gate':'PASS_V4_GRADER_COVERAGE','positive':1,'negative':7,'checks':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
