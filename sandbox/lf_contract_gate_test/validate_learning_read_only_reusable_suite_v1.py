#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys,json
ROOT=Path(__file__).resolve().parents[2]
S=ROOT/'sandbox/lf_contract_gate_test'
TESTS=[
 'validate_learning_consumer_benchmark.py',
 'validate_learning_consumer_context_pack_v2.py',
 'validate_learning_read_only_context_reader_cli_v1.py',
 'validate_learning_read_only_context_selector_v2.py',
 'validate_learning_consumer_dynamic_cluster_bindings_v1.py',
 'validate_learning_ui_architect_bindings_v1.py',
 'validate_learning_ui_architect_context_pack_v1.py',
 'validate_learning_ui_architect_50_cases_v1.py',
 'validate_learning_read_only_consumer_registry_v1.py',
 'validate_learning_read_only_readiness_matrix_v1.py',
 'validate_learning_read_only_consumer_resolver_v1.py',
 'validate_learning_read_only_context_service_v1.py',
 'validate_learning_read_only_context_service_contract_v1.py',
 'validate_learning_downstream_no_bypass_v1.py',
 'validate_learning_indirect_downstream_propagation_v1.py',
 'validate_learning_downstream_handoff_envelope_v1.py',
 'validate_learning_read_only_operational_flow_v1.py',
 'validate_learning_read_only_bridge_integration_v1.py',
 'validate_learning_bridge_source_state_20260901_v1.py',
 'validate_learning_behavioral_runtime_candidate_v1.py',
 'validate_learning_behavioral_readiness_v2.py',
 'validate_learning_additional_consumer_inventory_v1.py',
 'validate_learning_additional_consumer_capability_map_v1.py',
 'validate_learning_additional_consumers_50_cases_v1.py',
]
def main():
 results=[]
 for name in TESTS:
  r=subprocess.run([sys.executable,str(S/name)],cwd=ROOT,text=True,capture_output=True)
  results.append({'test':name,'returncode':r.returncode,'stdout':r.stdout.strip(),'stderr':r.stderr.strip()})
  if r.returncode!=0:
   print(json.dumps({'verdict':'FAIL','results':results},ensure_ascii=False)); return 1
 bench=subprocess.run([sys.executable,str(S/'run_learning_ui_architect_routing_benchmark_v1.py')],cwd=ROOT,text=True,capture_output=True)
 if bench.returncode!=0:
  print(bench.stdout); print(bench.stderr,file=sys.stderr); return 1
 b=json.loads(bench.stdout)
 if b['routing']['fp']!=0 or b['routing']['fn']!=0 or b['cases']!=50 or b['families']!=10: return 1
 add_bench=subprocess.run([sys.executable,str(S/'run_learning_additional_consumers_routing_benchmark_v1.py')],cwd=ROOT,text=True,capture_output=True)
 if add_bench.returncode!=0:
  print(add_bench.stdout); print(add_bench.stderr,file=sys.stderr); return 1
 ab=json.loads(add_bench.stdout)
 if ab['routing']['fp']!=0 or ab['routing']['fn']!=0 or ab['cases']!=50 or ab['families']!=10: return 1
 ref=json.loads((S/'learning_profiles_c3_live_reference_20260901_v1.json').read_text())
 state=json.loads((S/'learning_bridge_source_state_20260901_v1.json').read_text())
 if ref.get('reuse_rule')!='REFERENCE_PATTERN_ONLY_NOT_INHERITED_PASS' or any(x.get('conclusion')!='success' for x in ref.get('exact_head_workflows',[])): return 1
 if state.get('evidence_level')!='SOURCE_DECLARED_DB_UNVERIFIED_THIS_RUN': return 1
 print(json.dumps({'verdict':'PASS','validators':len(TESTS),'upstream_bridge':'LEARNING_BRIDGE_KB_CARD_LF','upstream_bridge_steps':25,'upstream_bridge_live_db':'UNVERIFIED','duplicate_learning_engine':False,'direct_learning_consumers':2,'indirect_downstream_consumers':2,'additional_consumers_discovered':2,'additional_consumers_bound':0,'additional_candidate_mappings':3,'additional_routing_cases':50,'additional_routing_families':10,'additional_routing':ab['routing'],'routing_cases':50,'routing_families':10,'ui_routing':b['routing'],'dynamic_exact_bindings':7,'dynamic_selector_llm_calls':0,'dynamic_selector_round_trips':0,'downstream_no_bypass_cases':40,'behavioral_runtime_candidate':'AVAILABLE_NOT_CANONICAL','behavioral_runtime_candidate_exact_head_ci':'4/4','behavioral_readiness':'FAIL_CLOSED_WAITING_CURRENT_GOVERNANCE_RECEIPT','selector_llm_calls':0,'selector_round_trips':0,'context_service_writes':0,'downstream_learning_llm_calls':0,'behavioral_profile_ab':'NOT_EXECUTED','profiles_c3_reference_head':ref['head'],'profiles_c3_pass_inherited':False,'production_impact':False},sort_keys=True))
 return 0
if __name__=='__main__': raise SystemExit(main())
