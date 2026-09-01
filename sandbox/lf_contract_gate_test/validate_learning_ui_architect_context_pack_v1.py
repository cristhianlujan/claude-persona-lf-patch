#!/usr/bin/env python3
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_ui_architect_context_pack_v1.json'
def fail(x): raise SystemExit('FAIL learning-ui-context-pack: '+x)
def main():
 d=json.loads(P.read_text())
 if d.get('status')!='CANDIDATO_READ_ONLY' or d.get('consumer_id')!='PERFIL-UI-ARCHITECT': fail('identity')
 u=d.get('upstream_authority') or {}; s=d.get('selection') or {}; a=d.get('authority') or {}
 if u.get('consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF' or u.get('current_required') is not True: fail('upstream')
 if u.get('precedence')!='PRODUCT_DIRECTION_FIRST': fail('precedence')
 if s.get('mode')!='DETERMINISTIC_EXACT_ID' or s.get('llm_selector_allowed') is not False or s.get('semantic_scope_expansion_allowed') is not False: fail('selector')
 if int(s.get('context_budget_bytes',999999))>5000 or int(s.get('max_evidence_refs_per_binding',99))>5: fail('budget')
 if a.get('eligible_grounding_status')!='GROUNDED' or a.get('consumer_ready_required') is not True: fail('eligibility')
 if a.get('competitive_evidence_is_context_not_product_truth') is not True or a.get('profile_source_mutation') is not False: fail('authority')
 if a.get('production_impact') is not False or a.get('automatic_promotion') is not False: fail('impact')
 if d.get('lifecycle_state')!='READY_FOR_BINDING': fail('lifecycle')
 print('LEARNING_UI_CONTEXT_PACK=PASS deterministic=1 llm_selector=0 max_bytes=5000 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
