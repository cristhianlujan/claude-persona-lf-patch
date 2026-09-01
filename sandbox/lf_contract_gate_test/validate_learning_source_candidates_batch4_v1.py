#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'sandbox/lf_contract_gate_test/learning_source_candidates_20260901_batch4.json'
EXPECTED_URLS={
 'https://reevalua.com/blog/cuotas-sin-intereses-costos-ocultos-peru',
 'https://reevalua.com/blog/sueldo-necesario-para-prestamo-10000-30000-50000-peru',
}
EXPECTED_QUEUES={
 'd364f9a9-69ee-439d-9190-d70d091b06b9',
 '199a4abd-3254-48d2-9caf-0621db4c8ca4',
}

def fail(msg): raise SystemExit('FAIL learning-source-batch4: '+msg)
def main():
 p=json.loads(PATH.read_text(encoding='utf-8'))
 if p.get('status')!='DIRECT_SOURCE_REVALIDATED_CAPTURE_PENDING': fail('status')
 if p.get('production_impact') is not False or p.get('direct_kb_write_allowed') is not False or p.get('consumer_ready_changes')!=0: fail('unsafe boundary')
 src=p.get('sources') or []
 if len(src)!=2: fail('source cardinality')
 if {x.get('url') for x in src}!=EXPECTED_URLS: fail('url set')
 if {x.get('queue_id') for x in src}!=EXPECTED_QUEUES: fail('queue set')
 if any(x.get('queue_state')!='PENDIENTE' for x in src): fail('queue state')
 if any(x.get('source_read')!='DIRECT_PAGE_OK_20260901' for x in src): fail('direct source read')
 if any(x.get('eligible_for_governed_capture') is not True for x in src): fail('capture eligibility')
 if any(x.get('new_card_required') is not False for x in src): fail('new card invariant')
 if p.get('exact_url_kb_dedup')!='2_OF_2_ZERO_EXACT_KB_ROWS': fail('exact kb dedup')
 if p.get('semantic_dedup')!='1_INCREMENTAL_PATTERN_1_ENRICHMENT_ONLY_NO_NEW_CARD': fail('semantic dedup')
 if not all(x.get('claim_boundary') and x.get('existing_authoritative_overlap_refs') for x in src): fail('authority boundary')
 print('LEARNING_SOURCE_BATCH4=PASS sources=2 direct=2 kb_exact_duplicates=0 new_cards=0 capture_pending=2')
 return 0
if __name__=='__main__': raise SystemExit(main())
