#!/usr/bin/env python3
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_behavioral_runtime_request_pair_v1.json'
EXPECTED_IDS={
'f67ffccd-e710-41f4-ae8c-eb5579227fc7','8b744f07-75f6-4332-9df5-12e7c6914bf1','02bcfdd4-6859-4d56-9fbc-02af0ddf65b5','a789f419-b05f-4eba-af99-015bd56d24d5','5500178a-d503-476c-be77-c99223b4d90c'}

def fail(msg): raise SystemExit(f'FAIL LEARNING_BEHAVIORAL_REQUEST_PAIR: {msg}')

def main():
 d=json.loads(P.read_text())
 if d['mode']!='READ_ONLY_SANDBOX_PRE_DISPATCH': fail('mode')
 ig=d['input_governance']
 if ig['current_run_id']!=215 or ig['screen_code']!='HOME_002' or not ig['current_full'] or not ig['current_cached']: fail('current governance')
 exp=d['experiment']
 if not (exp['same_profile'] and exp['same_model_runtime_required'] and exp['same_base_task'] and exp['same_judges_required']): fail('A/B invariants')
 if exp['single_variable_change']!='selected_competitive_context': fail('single variable')
 c=d['challenger']
 if c['context_selection']!='DETERMINISTIC_EXACT_ID' or c['llm_selector_calls']!=0 or c['selector_round_trips']!=0: fail('deterministic selector')
 rows=c['selected_evidence']
 if len(rows)!=5 or c['selected_count']!=5: fail('selected count')
 if {r['kb_id'] for r in rows}!=EXPECTED_IDS: fail('exact evidence ids')
 if any(not r['source_url'].startswith('https://') for r in rows): fail('source refs')
 required={'COMPETITIVE_EVIDENCE_IS_CONTEXT_NOT_PRODUCT_TRUTH','LF_CANONICAL_AUTHORITY_ALWAYS_WINS','NO_INVENTED_DISCOUNT_OR_ELIGIBILITY','NO_AUTOMATIC_PRODUCTION_IMPACT'}
 if not required.issubset(set(c['constraints'])): fail('authority constraints')
 dispatch=d['dispatch']
 if any(dispatch[k] for k in ('enqueue_performed','github_comment_emitted','external_dispatch_performed')): fail('dispatch must remain false')
 impact=d['impact']
 if impact['writes_to_product_state']!=0 or impact['automatic_impact'] or impact['production_authorized']: fail('impact boundary')
 if len(d['required_judges'])<8: fail('judge coverage')
 print('LEARNING_BEHAVIORAL_REQUEST_PAIR=PASS champion=1 challenger=1 selected=5 llm_selector=0 roundtrips=0 dispatch=0 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
