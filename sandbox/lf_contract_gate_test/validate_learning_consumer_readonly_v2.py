#!/usr/bin/env python3
from __future__ import annotations
import re, subprocess, sys
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
MATRIX=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_50_cases_v1.yaml'
CONTRACT=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_binding_benchmark_contract_v1.yaml'
BINDINGS=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_bindings_v2.yaml'
SELECTOR_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_learning_read_only_context_selector_v1.py'
GOV_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_product_director_input_governance_binding_v1.py'
ROUTING_BENCH=ROOT/'sandbox/lf_contract_gate_test/run_learning_consumer_routing_benchmark.py'
UI_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_learning_ui_consumer_readonly_v1.py'
DOWNSTREAM_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_learning_downstream_no_bypass_v1.py'
BEHAVIORAL_READINESS_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_learning_behavioral_readiness_v2.py'
SOURCE_CANDIDATE_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_learning_source_candidates_v1.py'
EXPECTED_FAMILIES={'COMPETITIVE_OFFER_INSIGHT','DEBT_EDUCATION','PAYMENT_NO_ADEUDO','DIGITAL_SELF_SERVICE','FINANCIAL_ALTERNATIVES','NEGOTIATION','OUT_OF_SCOPE_NO_INVOKE','CONFLICT_PRECEDENCE','STALE_LOW_GROUNDING','MULTI_DOMAIN_COMPLEX'}
EXPECTED_CAPS={'NEGOCIACION_DEUDA','ALTERNATIVAS_FINANCIERAS','EDUCACION_CREDITICIA','DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'}
REQUIRED={'consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','context_budget','lifecycle_state','version','source_learning_ids','champion_id','challenger_id','provenance'}
def fail(msg): raise SystemExit('FAIL learning-readonly-v2: '+msg)
def run(path):
 p=subprocess.run([sys.executable,str(path)],cwd=ROOT,capture_output=True,text=True)
 if p.returncode: fail(f'{path.name}: {p.stdout} {p.stderr}')
 return p.stdout.strip()
def blocks(text):
 starts=[m.start() for m in re.finditer(r'^  - binding_id:',text,re.M)]; starts.append(text.find('\nrollback:',starts[-1]) if starts else len(text)); return [text[starts[i]:starts[i+1]] for i in range(len(starts)-1)] if len(starts)>1 else []
def main():
 matrix=MATRIX.read_text(); contract=CONTRACT.read_text(); bindings=BINDINGS.read_text()
 case_lines=[x.strip() for x in matrix.splitlines() if x.strip().startswith('- {id:')]
 if len(case_lines)!=50: fail(f'cases={len(case_lines)}')
 fam=[]; pos=neg=0
 for line in case_lines:
  m=re.search(r'id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)',line)
  if not m: fail('malformed case')
  fam.append(m.group(2).strip()); pos+=m.group(3)=='true'; neg+=m.group(3)=='false'
 counts=Counter(fam)
 if set(counts)!=EXPECTED_FAMILIES or any(v!=5 for v in counts.values()): fail(f'family_counts={dict(counts)}')
 if 'selector_mode: DETERMINISTIC_EXACT_ID' not in contract or 'no_extra_llm_call: true' not in contract or 'no_extra_round_trip: true' not in contract: fail('contract deterministic invariants missing')
 b=blocks(bindings)
 if len(b)!=5: fail(f'bindings={len(b)}')
 caps=set()
 for block in b:
  fields=set(re.findall(r'^    ([a-z_]+):',block,re.M)); miss=REQUIRED-fields
  if miss: fail(f'missing_fields={sorted(miss)}')
  cap=re.search(r'^    capability_id:\s*(\S+)',block,re.M).group(1); caps.add(cap)
  if 'lifecycle_state: READY_FOR_BINDING' not in block: fail('lifecycle not READY_FOR_BINDING')
  refs=re.findall(r'public\.lf_knowledge_base/[0-9a-f-]{36}',block)
  if not 1<=len(refs)<=5: fail(f'{cap} evidence refs={len(refs)}')
 if caps!=EXPECTED_CAPS: fail(f'caps={caps}')
 print(run(SELECTOR_VALIDATOR)); print(run(GOV_VALIDATOR)); print(run(ROUTING_BENCH))
 print(f'LEARNING_CONSUMER_READONLY_V2=PASS cases=50 families=10 positive={pos} negative={neg} exact_bindings=5')
 print(run(UI_VALIDATOR))
 print(run(DOWNSTREAM_VALIDATOR))
 print(run(BEHAVIORAL_READINESS_VALIDATOR))
 print(run(SOURCE_CANDIDATE_VALIDATOR))
 print('LEARNING_READONLY_MULTI_CONSUMER_GATE=PASS direct_profiles=2 downstream_profiles=2 total_profiles=4 behavioral_runtime_invoked=0 staged_sources=5')
 return 0
if __name__=='__main__': raise SystemExit(main())
