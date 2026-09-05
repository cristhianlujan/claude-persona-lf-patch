#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_card_source_boundary_readback_v1.json').read_text())
def main():
 assert D['schema']=='LF_LEARNING_CARD_SOURCE_BOUNDARY_READBACK_V1' and D['mode']=='READ_ONLY'
 assert D['canonical_card_registry']=='public.lf_cards' and D['canonical_registry_keyword_matches']==0
 p=D['candidate_source_pr']; assert p['pr']==362 and p['state']=='OPEN' and p['merged'] is False and len(p['head_sha'])==40
 assert len(D['candidate_card_files'])==4 and all(x.startswith('cards/learning_competitive/') and x.endswith('/CARD.md') for x in D['candidate_card_files'])
 e=D['durable_lifecycle_events']; assert e['event_ids']==[9716,9717,9718,9719,9720] and e['disposition']=='EXISTING_CARD_ANCHOR' and e['card_write_executed'] is False
 assert D['interpretation']=='SOURCE_CANDIDATE_OR_ANCHOR_EVIDENCE_IS_NOT_CANONICAL_CARD_REGISTRY_MATERIALIZATION'
 assert D['binding_rule']=='NO_CARD_AUTHORITY_FROM_OPEN_UNMERGED_PR_OR_CARD_CREADA_LABEL_WHEN_CANONICAL_REGISTRY_READBACK_IS_ABSENT'
 assert D['automatic_card_creation'] is False and D['automatic_binding'] is False and D['production_authorized'] is False
 print('LEARNING_CARD_SOURCE_BOUNDARY=PASS candidate_pr=362 canonical_registry_matches=0 candidate_files=4 automatic_binding=false')
if __name__=='__main__': main()
