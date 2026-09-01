#!/usr/bin/env python3
from collections import Counter
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_ui_architect_50_cases_v1.yaml'
F={'HAPPY_PATH','NEGATIVE_NO_INVENTION','CARDINALITY_EXACT','TEMPORAL_CONDITIONAL','STATES_RECOVERY','INCOMPLETE_INPUT','CONFLICT_PRECEDENCE','MULTI_DOMAIN_COMPLEX','OUT_OF_SCOPE_NO_INVOKE','REGRESSION_HISTORICAL'}
def fail(x): raise SystemExit('FAIL learning-ui-50: '+x)
def main():
 d=yaml.safe_load(P.read_text()); cases=d.get('cases') or []
 if len(cases)!=50 or len({x['id'] for x in cases})!=50: fail('50 unique cases required')
 counts=Counter(x.get('family') for x in cases)
 if set(counts)!=F or any(v!=5 for v in counts.values()): fail(str(counts))
 if not any(x.get('invoke') is True for x in cases) or not any(x.get('invoke') is False for x in cases): fail('positive+negative')
 for x in cases:
  for k in ('capability','upstream_current','expected','prohibit'):
   if k not in x: fail(f"{x['id']} missing {k}")
 rules=d.get('rules') or {}
 if rules.get('same_inputs') is not True or rules.get('same_runtime_model') is not True or rules.get('same_judges') is not True: fail('comparison invariants')
 if rules.get('single_variable_change')!='selected_competitive_context' or rules.get('behavioral_execution') is not False: fail('scope')
 print('LEARNING_UI_50_MATRIX=PASS cases=50 families=10 behavioral=0')
 return 0
if __name__=='__main__': raise SystemExit(main())
