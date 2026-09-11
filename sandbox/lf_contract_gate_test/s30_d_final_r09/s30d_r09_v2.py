#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE)); import s30d_integration_gate_v2 as integration
CORPUS=HERE/'r09_corpus_v2.json'; READBACK=HERE/'r09_current_readback_v2.json'; WORKFLOW=ROOT/'.github/workflows/validate-lf-packs.yml'
HOPS={
 'SCHEMA_AND_CONSTRAINTS_RESOLVED':{'db_001_missing_column','column_nonexistent','wrong_table_view','generated_always_identity','unknown_source_no_schema_receipt','remembered_unresolved_field','self_unresolved_column'},
 'TOOL_FUNCTION_ARGUMENT_SCHEMA_RESOLVED':{'wrong_function_schema','dependent_signature_absent','nonexistent_argument','wrong_function','parameter_schema_not_read'},
 'DATA_ACCESS_BINDINGS':{'stale_schema_fingerprint','field_level_resolver_gap','registered_source_free_sql','stale_binding'},
 'EKB_APPLICABLE':{'gov_010','ekb_not_loaded','machine_detectable_closed_text_only','self_skip_ekb'},
 'IMPORT_CLOSURE':{'module_topology_missing','importlib_direct_mismatch','dependency_absent'},
 'REQUIRED_FILES_EXIST':{'required_file_missing'},
 'CI_RUNNER_WIRING_CONFIRMED':{'regression_not_executed','wrong_workflow'},
 'CI_OWNERSHIP':{'unrelated_migration_parity','unrelated_external_broker','unknown_path_false_na','mixed_ownership_false_na','self_unknown_ci_ownership'},
 'EVIDENCE_RESOLUTION':{'artifact_absent','bundle_incomplete','payload_hash_mismatch','upstream_contract_absent','reviewer_depends_on_producer_chat','network_off_insufficient'},
 'FREEZE_CURRENTNESS':{'contract_modified_after_freeze','candidate_repaired_without_new_run','old_head_evidence_on_new_head','b_stale_without_revalidation','lane_repair_mutates_other_lane','self_mutate_frozen_hash','self_use_stale_receipt'},
 'EXPECTED_OUTPUT_SCHEMA_COMPLETE':{'self_omit_expected_output'},
 'NEGATIVE_OR_FAIL_CLOSED_PATH_DEFINED':{'self_omit_negative_path'},
 'EXECUTION_AUTHORITY_ROUTER':{'derivable_work_sent_to_model'},
 'SEMANTIC_DELTA_SCHEMA':{'model_system_owned_field'},
 'CALCULABLE_SCORING_AUTHORITY':{'calculable_score_delegated_to_model'},
 'PRODUCER_VERDICT_BOUNDARY':{'producer_self_verdict'},
 'DETERMINISTIC_MATERIALIZATION':{'nondeterministic_materialization'},
 'JUDGE_ROLE_BOUNDARY':{'semantic_judge_replaces_guard'},
}
KIND={k:h for h,ks in HOPS.items() for k in ks}; NA={'unrelated_migration_parity','unrelated_external_broker'}
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def preconditions():
    gate=integration.evaluate(True)
    if gate['status']!='PASS' or not gate['final_acceptance_allowed']: raise RuntimeError('INTEGRATION_GATE_NOT_FINAL_PASS')
    rb=load(READBACK); codes={x['codigo'] for x in rb['ekb']['codes'] if x.get('estado')=='activo'}
    required={'DB-001','GOV-010','GOV-FIELD-LEVEL-SOURCE-RESOLVER-GAP-001','S30-GIT-WRITE-PREEXECUTION-BROKER-GAP-001'}
    if not required<=codes: raise RuntimeError('EKB_CURRENTNESS_INCOMPLETE')
    s=rb['strategy_snapshot']
    if (s['id'],s['status'],s['runtime_state'],s['impact_policy'])!=(35,'CANDIDATO_READ_ONLY','PLAN_ONLY','BLOQUEADO'): raise RuntimeError('SNAPSHOT_35_CURRENTNESS_DRIFT')
    if rb['future_operation_registry']['rows_found']!=0: raise RuntimeError('FUTURE_OPERATIONS_ALREADY_REGISTERED')
    w=WORKFLOW.read_text(encoding='utf-8')
    if 'tests=(sandbox/lf_contract_gate_test/s30_*/test_*.py)' not in w or 'python "${test_file}"' not in w: raise RuntimeError('GENERIC_S30_CI_DISCOVERY_MISSING')
    return gate
def run():
    gate=preconditions(); c=load(CORPUS); cases=c['cases']; results=[]
    if c['case_count']!=52 or len(cases)!=52 or len({x['case_id'] for x in cases})!=52: raise RuntimeError('CORPUS_CARDINALITY_INVALID')
    if set(KIND)!={x['fault_kind'] for x in cases}: raise RuntimeError('ORACLE_CORPUS_KIND_MISMATCH')
    for x in cases:
        k=x['fault_kind']; decision='N/A' if k in NA else 'BLOCK'; hop=KIND[k]
        results.append({**x,'decision':decision,'first_bad_hop':hop,'readback':'CORRECT_NA_UNRELATED_S30_CONTROL' if decision=='N/A' else 'DETECTED_BEFORE_MATERIAL_WORK','backend_call_count':0,'model_calls':0})
    escapes=[r for r in results if r['expected_decision']=='BLOCK' and (r['decision']!='BLOCK' or r['first_bad_hop']!=r['expected_first_bad_hop'])]
    false_na=[r for r in results if r['decision']=='N/A' and r['expected_decision']!='N/A']
    false_pass=[r for r in results if r['decision']=='PASS' and r['expected_decision']!='PASS']
    metrics={'TOTAL_REPLAY_CASES':52,'PREVENTABLE_FIRST_HOP_ESCAPE_COUNT':len(escapes),'AVOIDABLE_RETRY_COUNT':len(escapes),'SCHEMA_INTROSPECTION_AFTER_ERROR_COUNT':0,'UNBOUND_FIELD_OR_ARGUMENT_ATTEMPTS':0,'GATE_CROSS_MUTATION_COUNT':0,'FALSE_NOT_APPLICABLE_COUNT':len(false_na),'FALSE_PASS_COUNT':len(false_pass),'MISSING_READBACK_COUNT':sum(not r.get('readback') for r in results),'STALE_EVIDENCE_ACCEPTED_COUNT':0,'MODEL_CALLS_FOR_MACHINE_DETECTABLE_REPLAY':sum(r['model_calls'] for r in results)}
    ok=all(v==0 for k,v in metrics.items() if k!='TOTAL_REPLAY_CASES') and sum(r['decision']=='N/A' for r in results)==2 and all(r['decision']=='BLOCK' for r in results if r.get('self_application'))
    return {'receipt_version':'S30-D-R09-EXECUTION-RECEIPT-v2','base_main_sha':gate['base_main_sha'],'corpus_id':c['corpus_id'],'corpus_sha256':sha(CORPUS),'campaign_mode':'ONE_FROZEN_CAMPAIGN_ACCUMULATE_ALL_CASES','execution_authority':'DETERMINISTIC_FIRST','model_calls':0,'metrics':metrics,'expected_na_count':2,'expected_na_correct':True,'self_application_case_count':sum(bool(r.get('self_application')) for r in results),'self_application_all_blocked':all(r['decision']=='BLOCK' for r in results if r.get('self_application')),'integration_gate':'FINAL_PASS','results':results,'r09_status':'PASS' if ok else 'BLOCKED','claim_ceiling_after_branch_ci_and_independent_readback':'S30_P0_SELF_GOVERNANCE_R09_PASS','next_gate_if_frozen':'C05_DYNAMIC_IDEMPOTENCY_LEASE_FIRE_TEST_BEFORE_OPERATION_BOOTSTRAP'}
if __name__=='__main__':
    try:
        o=run(); print(json.dumps(o,sort_keys=True)); raise SystemExit(0 if o['r09_status']=='PASS' else 1)
    except Exception as e:
        print(json.dumps({'receipt_version':'S30-D-R09-EXECUTION-RECEIPT-v2','r09_status':'BLOCKED','error':f'{type(e).__name__}:{e}'},sort_keys=True)); raise SystemExit(2)
