#!/usr/bin/env python3
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_source_candidates_20260901_batch1.json'
ALLOWED={'Interbank','BBVA Peru','Scotiabank Peru','Banco Falabella Peru','Banco Ripley Peru'}
ALLOWED_DISPOSITIONS={'NEW_INCREMENTAL_MECHANIC','PARTIAL_INCREMENTAL','ENRICHMENT_ONLY_EXISTING_PATTERN'}

def fail(msg): raise SystemExit('FAIL learning-source-candidates: '+msg)
def main():
 p=json.loads(PATH.read_text())
 if p['status']!='SEMANTIC_DEDUP_COMPLETED_PIPELINE_CAPTURE_PENDING' or p['kb_write_allowed'] is not False or p['consumer_ready_allowed'] is not False: fail('unsafe lifecycle')
 d=p['dedup_evidence']
 if d.get('live_exact_url_dedup')!='5_OF_5_NEW_VS_KB_QUEUE_CAPTURE' or d.get('live_semantic_dedup')!='COMPLETED_READ_ONLY': fail('live dedup evidence missing')
 src=p['sources']
 if len(src)!=5 or {x['organization'] for x in src}!=ALLOWED: fail('source inventory mismatch')
 urls=[x['url'] for x in src]
 if len(set(urls))!=5 or any(not u.startswith('https://') for u in urls): fail('url invariant')
 dispositions=Counter()
 for x in src:
  if x['source_type']!='OFFICIAL_PRODUCT_PAGE': fail(x['source_id']+' source type')
  if x.get('semantic_disposition') not in ALLOWED_DISPOSITIONS: fail(x['source_id']+' disposition')
  if not x.get('incremental_signal') or not x.get('candidate_capabilities') or not x.get('observed_pattern') or not x.get('claim_boundary'): fail(x['source_id']+' incomplete')
  if x['status'] not in {'READY_FOR_GOVERNED_CAPTURE_NOT_KB','READY_FOR_GOVERNED_CAPTURE_NOT_NEW_CARD'}: fail(x['source_id']+' invalid status')
  dispositions[x['semantic_disposition']]+=1
 if dispositions['NEW_INCREMENTAL_MECHANIC']!=3 or dispositions['PARTIAL_INCREMENTAL']!=1 or dispositions['ENRICHMENT_ONLY_EXISTING_PATTERN']!=1: fail(f'dispositions={dict(dispositions)}')
 print('LEARNING_SOURCE_CANDIDATES=PASS sources=5 exact_new=5 semantic_new=3 partial=1 enrichment_only=1 kb_writes=0 consumer_ready=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
