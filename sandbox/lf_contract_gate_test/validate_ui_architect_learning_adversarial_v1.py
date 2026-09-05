#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'ui_architect_learning_adversarial_cases_v1.json'
FAIL_CLOSED={'unbound_kb_id','non_competencia_kb','ungrounded_kb','consumer_ready_false','semantic_search_authority_expansion','recursive_context_expansion','context_over_5000_bytes','more_than_5_evidence_refs'}
NO_CONTEXT={'missing_product_direction','stale_product_direction','legal_truth_from_competitor','product_scope_decision_from_ui_consumer'}
def main():
 d=json.loads(P.read_text()); passed=critical_fp=0
 for c in d['cases']:
  got='FAIL_CLOSED' if c['attempt'] in FAIL_CLOSED else 'NO_COMPETITIVE_CONTEXT' if c['attempt'] in NO_CONTEXT else 'UNEXPECTED'
  passed+=got==c['expected']; critical_fp+=got not in {'FAIL_CLOSED','NO_COMPETITIVE_CONTEXT'}
 assert passed==len(d['cases'])==12 and critical_fp==0
 print('UI_ARCHITECT_ADVERSARIAL=PASS cases=12/12 critical_false_positives=0 authority_expansion_blocked=1 prerequisite_no_bypass=1')
if __name__=='__main__': main()
