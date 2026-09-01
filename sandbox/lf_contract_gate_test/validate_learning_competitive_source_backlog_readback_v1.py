#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'learning_competitive_source_backlog_readback_v1.json'
def main():
 d=json.loads(P.read_text(encoding='utf-8'))
 assert d['schema']=='LF_LEARNING_COMPETITIVE_SOURCE_BACKLOG_READBACK_V1' and d['mode']=='READ_ONLY'
 s=d['sandbox_sources']; assert s['total']==s['active']==s['source_state_total']==19 and s['failed_sources']==0
 o=d['sandbox_observations']; assert o['total']==12 and o['current']==0 and o['discarded']==12
 assert d['sandbox_insights']['total']==0
 k=d['canonical_kb']; assert k['eligible_grounded_consumer_ready']==k['classified_eligible']==35 and k['unclassified_eligible']==0
 assert d['decision']=='NO_NEW_SAFE_CANONICAL_SOURCE_BATCH_FROM_SANDBOX_PIPELINE'
 assert d['automatic_promotion'] is False and d['production_authorized'] is False
 print('LEARNING_COMPETITIVE_SOURCE_BACKLOG=PASS sandbox_sources=19 active=19 failures=0 observations_current=0 discarded=12 insights=0 canonical_kb=35/35 unclassified=0')
if __name__=='__main__': main()
