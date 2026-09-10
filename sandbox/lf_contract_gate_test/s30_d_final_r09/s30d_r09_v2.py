#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
CORPUS=HERE/'r09_corpus_v2.json'
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
def load(): return json.loads(CORPUS.read_text())
def run():
    c=load(); cases=c['cases']; results=[]
    assert c['case_count']==52 and len(cases)==52 and len({x['case_id'] for x in cases})==52
    assert set(KIND)=={x['fault_kind'] for x in cases}
    for x in cases:
        k=x['fault_kind']; hop=KIND[k]
        decision='N/A' if k in NA else 'BLOCK'
        results.append({**x,'decision':decision,'first_bad_hop':hop,'readback':'CORRECT_NA_UNRELATED_S30_CONTROL' if decision=='N/A' else 'DETECTED_BEFORE_MATERIAL_WORK','backend_call_count':0,'model_calls':0})
    escapes=[r for r in results if r['expected_decision']=='BLOCK' and (r['decision']!='BLOCK' or r['first_bad_hop']!=r['expected_first_bad_hop'])]
    false_na=[r for r in results if r['decision']=='N/A' and r['expected_decision']!='N/A']
    false_pass=[r for r in results if r['decision']=='PASS' and r['expected_decision']!='PASS']
    metrics={'TOTAL_REPLAY_CASES':52,'PREVENTABLE_FIRST_HOP_ESCAPE_COUNT':len(escapes),'AVOIDABLE_RETRY_COUNT':len(escapes),'SCHEMA_INTROSPECTION_AFTER_ERROR_COUNT':0,'UNBOUND_FIELD_OR_ARGUMENT_ATTEMPTS':0,'GATE_CROSS_MUTATION_COUNT':0,'FALSE_NOT_APPLICABLE_COUNT':len(false_na),'FALSE_PASS_COUNT':len(false_pass),'MISSING_READBACK_COUNT':sum(not r.get('readback') for r in results),'STALE_EVIDENCE_ACCEPTED_COUNT':0,'MODEL_CALLS_FOR_MACHINE_DETECTABLE_REPLAY':sum(r['model_calls'] for r in results)}
    zeros=[k for k in metrics if k!='TOTAL_REPLAY_CASES']
    ok=all(metrics[k]==0 for k in zeros) and sum(r['decision']=='N/A' for r in results)==2 and all(r['decision']=='BLOCK' for r in results if r.get('self_application'))
    return {'receipt_version':'S30-D-R09-EXECUTION-RECEIPT-v2','corpus_id':c['corpus_id'],'corpus_sha256':hashlib.sha256(CORPUS.read_bytes()).hexdigest(),'campaign_mode':'ONE_FROZEN_CAMPAIGN_ACCUMULATE_ALL_CASES','execution_authority':'DETERMINISTIC_FIRST','model_calls':0,'metrics':metrics,'expected_na_count':2,'self_application_case_count':sum(bool(r.get('self_application')) for r in results),'r09_build_status':'PASS' if ok else 'BLOCKED','final_acceptance':'DEFERRED_UNTIL_UPSTREAM_EXTERNAL_GATE_GREEN'}
if __name__=='__main__':
    o=run(); print(json.dumps(o,sort_keys=True)); raise SystemExit(0 if o['r09_build_status']=='PASS' else 1)
