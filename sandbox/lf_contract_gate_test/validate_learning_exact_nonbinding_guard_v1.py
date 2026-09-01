#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_exact_nonbinding_guard_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_EXACT_NONBINDING_GUARD_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['fallback']=='NO_COMPETITIVE_CONTEXT','FALLBACK')
req(D['selection_rule']=='NO_EXACT_BINDING_MEANS_NO_CONTEXT','SELECTION_RULE')
req(len(D['explicit_nonbindings'])==4,'NONBINDINGS_COUNT')
req(len({x['consumer_id'] for x in D['explicit_nonbindings']})==4,'NONBINDINGS_UNIQUE')
req(len(D['unbound_clusters'])==3,'UNBOUND_COUNT')
for x in D['unbound_clusters']:
    req(x['existing_exact_card_observed'] is False,'NO_CARD_'+x['cluster_code'])
    req(x['automatic_card_creation'] is False,'NO_AUTO_CARD_'+x['cluster_code'])
req({x['next_state'] for x in D['unbound_clusters']} <= {'READY_FOR_BINDING_ONLY','NO_CARD'},'UNBOUND_STATES')
for k in ('semantic_search','automatic_binding','automatic_card_creation','automatic_impact','production_authorized'):
    req(D[k] is False,'AUTH_'+k.upper())
print('LEARNING_EXACT_NONBINDING_GUARD=PASS explicit_nonbindings=4 unbound_clusters=3 semantic_search=false automatic_binding=false automatic_card_creation=false')
