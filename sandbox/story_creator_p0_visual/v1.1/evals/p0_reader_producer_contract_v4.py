#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,sys,tempfile
from pathlib import Path
import cv2,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
import p0_full_reader_v4 as reader
from p0_visual_graders_v4 import run_all,canonical_sha
from p0_visual_discovery_v4 import union_findings,coverage_receipt
POLICY={'schema_version':'p0-sweep-materiality-policy/v1','text_confidence_strong_min':45.0,'text_confidence_long_min':35.0,'text_long_min_alnum':4,'object_material_area_min_px2':900,'rationale':'producer-contract fixture mirrors product policy'}

def line(text,x,w,conf=92.0):return {'text':text,'confidence':conf,'region':{'x':x,'y':20,'width':w,'height':24}}
def blank_sweep(candidate,source_sha):
 return {'schema_version':'p0-independent-omission-sweep-v4/v1','execution_id':'SW-PRODUCER','source_sha256':source_sha,'candidate_sha256':canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'}),'width':candidate['width'],'height':candidate['height'],'status':'COMPLETE','fresh_source_read':True,'observations':[],'regions':[{'region_id':r,'material':True,'observed_count':0,'represented_count':0,'uncertain_count':0,'unrepresented_count':0,'sweep_status':'COMPLETE','evidence_refs':[]} for r in ('FULL','LEFT','RIGHT')],'object_sweep':{'detector':'TEST_FIXTURE','raw_count':0,'deduped_count':0,'emitted_count':0,'limit':60,'truncated':False},'materiality_policy':POLICY,'unrepresented_observation_ids':[],'unsupported_candidate_ids':[],'candidate_support_uncertain_ids':[],'errors':[]}
def main():
 original=reader.ocr_lines
 with tempfile.TemporaryDirectory() as td:
  p=Path(td)/'source.png';cv2.imwrite(str(p),np.full((120,420,3),255,np.uint8));source_sha=hashlib.sha256(p.read_bytes()).hexdigest()
  observations={3:[line('Cuenta bancaria principal',20,300)],6:[line('Cuenta bancaria',20,185),line('principal',215,105)],11:[line('Cuenta bancaria principal',20,300)],12:[line('Cuenta bancaria principal',20,300)]}
  reader.ocr_lines=lambda image,psm:json.loads(json.dumps(observations[psm]))
  try:candidate=reader.full_reader(str(p),{'cycle_id':'C-PROD','pass_id':'P-PROD','reader_execution_id':'R-PROD','source_sha256':source_sha,'remediation_state':{}})
  finally:reader.ocr_lines=original
  text_elements=[e for e in candidate['elements'] if e.get('visible_text')]
  assert len(text_elements)==1,text_elements
  e=text_elements[0];assert e.get('text_group_consistency') is False,e;assert e.get('text_group_observation_counts')=={'3':1,'6':2,'11':1,'12':1},e.get('text_group_observation_counts');assert len(e.get('source_observation_refs') or [])>=4
  sweep=blank_sweep(candidate,source_sha);ctx={'cycle_id':'C-PROD','pass_id':'P-PROD','reader_execution_id':'R-PROD','source_sha256':source_sha,'candidate_sha256':canonical_sha({k:v for k,v in candidate.items() if k!='reader_execution_id'}),'coverage_execution_id':'COV-PROD','independent_sweep':sweep};outs=run_all(candidate,ctx);findings=union_findings(outs);cats={f['category'] for f in findings};cov=coverage_receipt(candidate,outs,ctx)
  assert 'TEXT_GROUPING_MISMATCH' in cats,(cats,e);assert not cov['coverage_pass']
  print(json.dumps({'gate':'PASS_V4_READER_PRODUCER_CONTRACT','full_reader_function':'p0_full_reader_v4.full_reader','reader_emitted_text_group_consistency':e['text_group_consistency'],'observation_counts':e['text_group_observation_counts'],'source_observation_ref_count':len(e['source_observation_refs']),'grader_finding':'TEXT_GROUPING_MISMATCH','coverage_pass':cov['coverage_pass']},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
