#!/usr/bin/env python3
from __future__ import annotations
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
MATRIX=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_50_cases_v1.yaml'
CONTRACT=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_binding_benchmark_contract_v1.yaml'
BINDINGS=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_bindings_v1.yaml'
BINDING_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_product_director_input_governance_binding_v1.py'
READ_ONLY_SELECTOR_VALIDATOR=ROOT/'sandbox/lf_contract_gate_test/validate_learning_read_only_context_selector_v1.py'
EXPECTED_FAMILIES={'COMPETITIVE_OFFER_INSIGHT','DEBT_EDUCATION','PAYMENT_NO_ADEUDO','DIGITAL_SELF_SERVICE','FINANCIAL_ALTERNATIVES','NEGOTIATION','OUT_OF_SCOPE_NO_INVOKE','CONFLICT_PRECEDENCE','STALE_LOW_GROUNDING','MULTI_DOMAIN_COMPLEX'}
EXPECTED_CAPABILITIES={'NEGOCIACION_DEUDA','ALTERNATIVAS_FINANCIERAS','EDUCACION_CREDITICIA'}
REQUIRED_CONTRACT_TERMS={'consumer_id','consumer_type','capability_id','invoke_when','must_not_invoke_when','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','champion_id','challenger_id','READY_FOR_BINDING','DETERMINISTIC_FIRST','authority_pass_pct: 100','critical_must_not_invoke_false_positives: 0','automatic_impact: BLOQUEADO','production: BLOQUEADO','execution_consumer_role: CONTEXT_PACK','profile_asset_code_as_governance_consumer: FORBIDDEN','selector_mode: DETERMINISTIC_EXACT_ID','no_extra_llm_call: true','no_extra_round_trip: true','initial_benchmark_cases: 50','preferred_shape: 10_FAMILIES_X_5_CASES'}
REQUIRED_BINDING_FIELDS={'version','consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when','input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref','judges','fallback','timeout_budget','context_budget','lifecycle_state','source_learning_ids','champion_id','challenger_id','provenance'}

def fail(msg): raise SystemExit(f'FAIL learning-consumer-benchmark: {msg}')

def binding_blocks(text: str) -> list[str]:
 starts=[m.start() for m in re.finditer(r'^  - binding_id:',text,re.M)]
 if not starts:
  return []
 end=text.find('\nexcluded_learning_refs:',starts[-1])
 if end<0: end=len(text)
 starts.append(end)
 return [text[starts[i]:starts[i+1]] for i in range(len(starts)-1)]

def validate_bindings(text: str) -> None:
 blocks=binding_blocks(text)
 if len(blocks)!=3: fail(f'expected 3 exact binding blocks, found {len(blocks)}')
 seen_ids=set(); seen_caps=set()
 for block in blocks:
  first=block.splitlines()[0]
  binding_id=first.split(':',1)[1].strip()
  if not binding_id or binding_id in seen_ids: fail(f'invalid or duplicate binding_id: {binding_id}')
  seen_ids.add(binding_id)
  fields=set(re.findall(r'^    ([a-z_]+):',block,re.M))
  missing=sorted(REQUIRED_BINDING_FIELDS-fields)
  if missing: fail(f'{binding_id} missing fields: {missing}')
  match=re.search(r'^    capability_id:\s*(\S+)\s*$',block,re.M)
  if not match: fail(f'{binding_id} capability_id unresolved')
  capability=match.group(1)
  if capability not in EXPECTED_CAPABILITIES: fail(f'{binding_id} unexpected capability: {capability}')
  if capability in seen_caps: fail(f'duplicate capability binding: {capability}')
  seen_caps.add(capability)
  if 'lifecycle_state: READY_FOR_BINDING' not in block: fail(f'{binding_id} lifecycle must remain READY_FOR_BINDING')
  evidence_refs=re.findall(r'^      - public\.lf_knowledge_base/[0-9a-f-]{36}\s*$',block,re.M)
  if not evidence_refs or len(evidence_refs)>5: fail(f'{binding_id} selected evidence refs must be 1..5, found {len(evidence_refs)}')
  learning_ids=re.findall(r'^      - ([0-9a-f-]{36})\s*$',block,re.M)
  if not learning_ids: fail(f'{binding_id} source_learning_ids empty')
 if seen_caps!=EXPECTED_CAPABILITIES: fail(f'capability set mismatch: {sorted(seen_caps)}')
 if text.count('reason: REGULATORY_AUTHORITY_SOURCE_NOT_COMPETITIVE_PROFILE_CONTEXT')!=1: fail('SBS regulatory no-invoke exclusion missing')
 if text.count('reason: BRAND_OR_COPY_SCOPE_NOT_PRODUCT_DIRECTOR_COMPETITIVE_CAPABILITY')!=1: fail('brand/copy no-invoke exclusion missing')
 if text.count('reason: LEGAL_REGULATORY_TRUTH_REQUIRES_INDEPENDENT_AUTHORITY')!=1: fail('legal/regulatory no-invoke exclusion missing')

def run_validator(path: Path, label: str) -> str:
 completed=subprocess.run([sys.executable,str(path)],cwd=ROOT,check=False,capture_output=True,text=True)
 if completed.returncode!=0: fail(f'{label} failed: {completed.stdout} {completed.stderr}')
 return completed.stdout.strip()

def main():
 matrix=MATRIX.read_text(encoding='utf-8'); contract=CONTRACT.read_text(encoding='utf-8'); bindings=BINDINGS.read_text(encoding='utf-8')
 case_lines=[line.strip() for line in matrix.splitlines() if line.strip().startswith('- {id:')]
 if len(case_lines)!=50: fail(f'expected 50 cases, found {len(case_lines)}')
 ids=[]; families=[]; invokes=Counter()
 for line in case_lines:
  m=re.search(r'id:\s*([^,}]+),\s*family:\s*([^,}]+),\s*invoke:\s*(true|false),\s*expect:\s*([^,}]+),\s*prohibit:\s*([^,}]+)',line)
  if not m: fail(f'malformed case line: {line}')
  case_id,family,invoke,expect,prohibit=[v.strip() for v in m.groups()]
  if not expect or not prohibit: fail(f'case {case_id} missing expectation/prohibition')
  ids.append(case_id); families.append(family); invokes[invoke]+=1
 if len(set(ids))!=50: fail('case IDs are not unique')
 counts=Counter(families)
 if set(counts)!=EXPECTED_FAMILIES: fail(f'family set mismatch: {sorted(counts)}')
 if any(count!=5 for count in counts.values()): fail(f'each family must have exactly 5 cases: {dict(sorted(counts.items()))}')
 if invokes['true']==0 or invokes['false']==0: fail('benchmark must contain positive and should-not-invoke cases')
 missing=sorted(term for term in REQUIRED_CONTRACT_TERMS if term not in contract)
 if missing: fail(f'contract missing required terms: {missing}')
 if 'same_inputs: true' not in matrix or 'same_model_runtime: true' not in matrix or 'same_judges: true' not in matrix: fail('champion/challenger comparison invariants missing')
 validate_bindings(bindings)
 print(run_validator(BINDING_VALIDATOR,'input governance binding selftest'))
 print(run_validator(READ_ONLY_SELECTOR_VALIDATOR,'read-only learning selector selftest'))
 print('LEARNING_CONSUMER_BINDINGS=PASS exact_bindings=3')
 print('LEARNING_CONSUMER_BENCHMARK_VERDICT=PASS'); print(f"cases=50 families=10 positive={invokes['true']} negative={invokes['false']}")
 for family,count in sorted(counts.items()): print(f'family={family} cases={count}')
 return 0
if __name__=='__main__': raise SystemExit(main())
