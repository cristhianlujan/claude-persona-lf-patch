#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_competitive_exact_url_probe_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_COMPETITIVE_EXACT_URL_PROBE_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['operation_code']=='BUILD_COMPETITIVE_INTELLIGENCE_MARKETPLACE_LF','OPERATION')
req(D['operation_status']=='CANDIDATO_READ_ONLY','STATUS')
req(D['step_contract_count_observed']==0,'NO_STEP_CONTRACTS')
P=D['probe_policy']
req(P['selection']=='EXACT_SOURCE_ID_AND_EXACT_REGISTERED_URL_ONLY','EXACT_SELECTION')
for k in ('free_semantic_search','automatic_ingest','observation_write','insight_write','kb_write','authority_created','production_authorized'):
    req(P[k] is False,'BOUNDARY_'+k.upper())
req(P['fallback']=='NO_PERSISTED_COMPETITIVE_OBSERVATION','FALLBACK')
req(D['attempted']==5 and D['accessible']==5 and len(D['sources'])==5,'CARDINALITY')
ids=[x['source_id'] for x in D['sources']]
urls=[x['url'] for x in D['sources']]
req(len(ids)==len(set(ids))==5,'UNIQUE_SOURCE_IDS')
req(len(urls)==len(set(urls))==5,'UNIQUE_URLS')
req(all(x['probe_result']=='ACCESSIBLE_TEXT' for x in D['sources']),'ACCESSIBLE')
req(all(x['url'].startswith('https://') and x['source_id'] and x['competitor_id'] for x in D['sources']),'SOURCE_BINDING')
req(D['durable_boundary']=='URL_ACCESS_PROBE_ONLY_NOT_A_COMPETITIVE_OBSERVATION','BOUNDARY')
req(D['next_gate']=='CANONICAL_OPERATION_STEP_CONTRACTS_AND_RUN_STATE_REQUIRED_BEFORE_SANDBOX_OBSERVATION_WRITE','NEXT_GATE')
print('LEARNING_COMPETITIVE_EXACT_URL_PROBE=PASS sources=5/5 persisted_observations=0 authority_created=false production_authorized=false')
