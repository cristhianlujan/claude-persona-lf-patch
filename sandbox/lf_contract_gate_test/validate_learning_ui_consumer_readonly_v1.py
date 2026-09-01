#!/usr/bin/env python3
from __future__ import annotations
import re,subprocess,sys
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MATRIX=ROOT/'sandbox/lf_contract_gate_test/learning_ui_consumer_50_cases_v1.yaml'
BINDINGS=ROOT/'sandbox/lf_contract_gate_test/learning_ui_consumer_bindings_v1.yaml'
BENCH=ROOT/'sandbox/lf_contract_gate_test/run_learning_ui_consumer_routing_benchmark.py'
EXPECTED_FAMILIES={'HAPPY_PATH_CREATE','HAPPY_PATH_REMEDIATE','CARDINALITY_BOUNDED_CONTEXT','TEMPORAL_CONDITIONAL','STATES_RECOVERY','INPUTS_INCOMPLETE','CONFLICT_PRECEDENCE','MULTI_DOMAIN_COMPLEX','OUT_OF_SCOPE_NO_INVOKE','REGRESSION_HISTORICAL_FAILURES'}
EXPECTED_CAPS={'DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'}
REQUIRED={'version','consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','context_budget','lifecycle_state','source_learning_ids','champion_id','challenger_id','provenance'}
def fail(msg): raise SystemExit('FAIL learning-ui-readonly-v1: '+msg)
def blocks(text):
 starts=[m.start() for m in re.finditer(r'^  - binding_id:',text,re.M)]; starts.append(text.find('\nrollback:',starts[-1]) if starts else len(text)); return [text[starts[i]:starts[i+1]] for i in range(len(starts)-1)] if len(starts)>1 else []
def main():
 matrix=MATRIX.read_text(); bindings=BINDINGS.read_text(); lines=[x.strip() for x in matrix.splitlines() if x.strip().startswith('- {id:')]
 if len(lines)!=50: fail(f'cases={len(lines)}')
 fam=[]; pos=neg=0
 for line in lines:
  m=re.search(r'id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)',line)
  if not m: fail('malformed case')
  fam.append(m.group(2).strip()); pos+=m.group(3)=='true'; neg+=m.group(3)=='false'
 counts=Counter(fam)
 if set(counts)!=EXPECTED_FAMILIES or any(v!=5 for v in counts.values()): fail(f'family_counts={dict(counts)}')
 if pos!=25 or neg!=25: fail(f'expected 25/25 got {pos}/{neg}')
 b=blocks(bindings)
 if len(b)!=2: fail(f'bindings={len(b)}')
 caps=set()
 for block in b:
  fields=set(re.findall(r'^    ([a-z_]+):',block,re.M)); miss=REQUIRED-fields
  if miss: fail(f'missing_fields={sorted(miss)}')
  cap=re.search(r'^    capability_id:\s*(\S+)',block,re.M).group(1); caps.add(cap)
  if 'product_direction_authorized_current' not in block: fail(f'{cap} missing product direction precondition')
  refs=re.findall(r'public\.lf_knowledge_base/[0-9a-f-]{36}',block)
  if not 1<=len(refs)<=5: fail(f'{cap} refs={len(refs)}')
 if caps!=EXPECTED_CAPS: fail(f'caps={caps}')
 p=subprocess.run([sys.executable,str(BENCH)],cwd=ROOT,capture_output=True,text=True)
 if p.returncode: fail(f'benchmark: {p.stdout} {p.stderr}')
 print(p.stdout.strip()); print('LEARNING_UI_CONSUMER_READONLY_V1=PASS cases=50 families=10 positive=25 negative=25 exact_bindings=2'); return 0
if __name__=='__main__': raise SystemExit(main())
