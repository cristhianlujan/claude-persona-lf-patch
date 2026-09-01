#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_source_candidates_20260901_batch1.json'
ALLOWED={'Interbank','BBVA Peru','Scotiabank Peru','Banco Falabella Peru','Banco Ripley Peru'}

def fail(msg): raise SystemExit('FAIL learning-source-candidates: '+msg)
def main():
 p=json.loads(PATH.read_text())
 if p['status']!='DISCOVERED_LIVE_KB_DEDUP_REQUIRED' or p['kb_write_allowed'] is not False or p['consumer_ready_allowed'] is not False: fail('unsafe lifecycle')
 if p['dedup_evidence']['live_kb_dedup']!='UNAVAILABLE_SQL_CHANNEL_BLOCKED': fail('dedup limitation hidden')
 src=p['sources']
 if len(src)!=5 or {x['organization'] for x in src}!=ALLOWED: fail('source inventory mismatch')
 urls=[x['url'] for x in src]
 if len(set(urls))!=5 or any(not u.startswith('https://') for u in urls): fail('url invariant')
 for x in src:
  if x['source_type']!='OFFICIAL_PRODUCT_PAGE' or x['status']!='DISCOVERED_DEDUP_PENDING': fail(x['source_id']+' invalid status')
  if not x['candidate_capabilities'] or not x['observed_pattern'] or not x['claim_boundary']: fail(x['source_id']+' incomplete')
 print('LEARNING_SOURCE_CANDIDATES=PASS sources=5 live_kb_dedup=REQUIRED kb_writes=0 consumer_ready=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
