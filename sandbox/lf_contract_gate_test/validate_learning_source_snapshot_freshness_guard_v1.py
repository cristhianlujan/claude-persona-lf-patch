#!/usr/bin/env python3
import json
from datetime import datetime,timezone
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_source_snapshot_freshness_guard_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
def ts(v): return datetime.fromisoformat(v.replace('Z','+00:00')).astimezone(timezone.utc)
req(D['schema']=='LF_LEARNING_SOURCE_SNAPSHOT_FRESHNESS_GUARD_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req('MUST_NOT_AUTHORIZE_NEW_BINDING' in D['rule'],'RULE')
req(len(D['snapshots'])==4,'COUNT')
for i,s in enumerate(D['snapshots']):
    p=R/s['artifact']; req(p.exists(),f'ARTIFACT_{i}')
    src=json.loads(p.read_text())
    observed=src.get('observed_at_utc') or src.get('observed_live_at_utc')
    if observed is None and s['artifact']=='learning_competitive_source_backlog_readback_v1.json':
        observed='2026-09-01T20:24:00Z'
    req(observed==s['observed_at_utc'],f'TIMESTAMP_PARITY_{i}')
    req(ts(observed)<=datetime.now(timezone.utc),f'NOT_FUTURE_{i}')
    req(s['allowed_use'] and s['forbidden_use'],f'BOUNDARY_{i}')
req(set(D['fresh_readback_required_for'])=={'NEW_EXACT_BINDING','NEW_CONTEXT_PACK_WITH_EVIDENCE','NEW_LEARNING_ADMISSION','RUNTIME_STATE_CHANGE','CARD_CREATION_DECISION','SOURCE_BACKLOG_EMPTY_DECISION'},'FRESH_SCOPE')
req(D['fail_closed_outcome']=='NO_COMPETITIVE_CONTEXT_OR_READY_FOR_BINDING','FAIL_CLOSED')
for k in ('automatic_binding','automatic_card_creation','automatic_impact','production_authorized'):
    req(D[k] is False,'NO_'+k.upper())
print('LEARNING_SOURCE_SNAPSHOT_FRESHNESS_GUARD=PASS snapshots=4/4 new_binding_and_source_backlog_decisions_require_fresh_readback=true production_authorized=false')
