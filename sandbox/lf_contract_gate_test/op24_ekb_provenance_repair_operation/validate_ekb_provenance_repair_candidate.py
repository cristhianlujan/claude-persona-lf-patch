#!/usr/bin/env python3
import argparse
import json
import yaml

REQUIRED_KEYS = {
    'version','status','operation','source_model','asset_type','router_action',
    'operation_family','operation_domain','operation_type','applies_to_asset_type',
    'purpose','authority','state_ceiling','required_before_any_durable_write',
    'write_contract','negative_controls','required_after_write','router_binding_candidate','promotion_rule'
}
REQUIRED_NEGATIVES = {
    'missing_router_blocks','source_ref_already_present_blocks','row_evidence_missing_exact_ref_blocks',
    'unresolved_source_ref_blocks','conflicting_source_candidates_block','target_count_drift_blocks',
    'orphan_execution_id_blocks','unrelated_execution_scope_blocks','sibling_or_lote_inheritance_blocks',
    'durable_write_without_readback_blocks'
}
REQUIRED_ASSERTIONS = {
    'router_current','exact_targets','self_evidence','independent_resolution','contradiction_first',
    'no_inference','null_only','execution_provenance','protected_columns','exact_count',
    'second_readback','unresolved_preserved','no_promotion','rollback'
}

def load(path):
    with open(path, 'r', encoding='utf-8') as fh:
        obj = yaml.safe_load(fh)
    if not isinstance(obj, dict):
        raise ValueError(f'YAML_OBJECT_REQUIRED:{path}')
    return obj

def validate(contract, steps_doc, judge):
    errors=[]
    missing=sorted(REQUIRED_KEYS-set(contract))
    if missing: errors.append('CONTRACT_KEYS_MISSING:'+','.join(missing))
    expected={
        'operation':'EKB_PROVENANCE_REPAIR_LF','status':'CANDIDATO_READ_ONLY','asset_type':'EKB',
        'router_action':'PROVENANCE_REPAIR','operation_type':'UPDATE_PROTOCOL','applies_to_asset_type':'EKB'
    }
    for k,v in expected.items():
        if contract.get(k)!=v: errors.append(f'CONTRACT_MISMATCH:{k}')
    ceiling=contract.get('state_ceiling') or {}
    if ceiling.get('runtime_allowed') is not False: errors.append('RUNTIME_NOT_BLOCKED')
    if ceiling.get('production_write_allowed_by_candidate') is not False: errors.append('CANDIDATE_PRODUCTION_WRITE_ALLOWED')
    if ceiling.get('automatic_impact')!='BLOQUEADO': errors.append('AUTOMATIC_IMPACT_NOT_BLOCKED')
    wc=contract.get('write_contract') or {}
    if wc.get('source_ref_overwrite_forbidden') is not True: errors.append('SOURCE_REF_OVERWRITE_NOT_FORBIDDEN')
    if wc.get('content_rewrite_forbidden') is not True: errors.append('CONTENT_REWRITE_NOT_FORBIDDEN')
    if wc.get('inferred_lote_or_sibling_provenance_forbidden') is not True: errors.append('INFERRED_PROVENANCE_NOT_FORBIDDEN')
    if set(wc.get('allowed_columns') or []) != {'source_ref','updated_at','updated_by_execution_id'}:
        errors.append('ALLOWED_COLUMNS_NOT_EXACT')
    neg=set(contract.get('negative_controls') or [])
    miss=sorted(REQUIRED_NEGATIVES-neg)
    if miss: errors.append('NEGATIVE_CONTROLS_MISSING:'+','.join(miss))
    rb=contract.get('router_binding_candidate') or {}
    router_expected={
        'asset_type':'EKB','action_code':'PROVENANCE_REPAIR','operation_code':'EKB_PROVENANCE_REPAIR_LF',
        'operation_resolution':'STATIC','requires_existing_target':True,'requires_missing_target':False,
        'write_allowed':True,'status':'CANDIDATE_SANDBOX'
    }
    for k,v in router_expected.items():
        if rb.get(k)!=v: errors.append(f'ROUTER_BINDING_MISMATCH:{k}')
    steps=steps_doc.get('steps')
    if not isinstance(steps,list) or len(steps)!=18:
        errors.append('STEP_COUNT_MISMATCH')
    else:
        orders=[x.get('order') for x in steps if isinstance(x,dict)]
        if orders!=list(range(1,19)): errors.append('STEP_ORDER_NOT_CONTIGUOUS')
        ids=[x.get('id') for x in steps if isinstance(x,dict)]
        if len(ids)!=len(set(ids)): errors.append('STEP_IDS_NOT_UNIQUE')
        for required in ('router','self_evidence_gate','independent_ref_resolution','contradiction_check','execution_provenance','rollback_canary','durable_write_gate','independent_readback','unresolved_preservation','close'):
            if required not in ids: errors.append('STEP_MISSING:'+required)
    if steps_doc.get('operation')!='EKB_PROVENANCE_REPAIR_LF': errors.append('STEPS_OPERATION_MISMATCH')
    assertions={x.get('id') for x in judge.get('required_assertions') or [] if isinstance(x,dict)}
    miss=sorted(REQUIRED_ASSERTIONS-assertions)
    if miss: errors.append('JUDGE_ASSERTIONS_MISSING:'+','.join(miss))
    if judge.get('operation')!='EKB_PROVENANCE_REPAIR_LF': errors.append('JUDGE_OPERATION_MISMATCH')
    if judge.get('verdicts')!=['PASS','FAIL']: errors.append('JUDGE_VERDICTS_MISMATCH')
    claim=str(judge.get('claim_ceiling') or '')
    for term in ('no autoriza','escritura durable','producción'):
        if term not in claim: errors.append('CLAIM_CEILING_INCOMPLETE:'+term)
    if 'no autoriza registro Router ACTIVE' not in str(contract.get('promotion_rule') or ''):
        errors.append('PROMOTION_RULE_NOT_FAIL_CLOSED')
    return errors

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--contract',required=True); ap.add_argument('--steps',required=True); ap.add_argument('--judge',required=True); ap.add_argument('--json',action='store_true')
    args=ap.parse_args()
    errors=validate(load(args.contract),load(args.steps),load(args.judge))
    result={'valid':not errors,'blocking_codes':errors}
    print(json.dumps(result,sort_keys=True) if args.json else ('PASS_EKB_PROVENANCE_REPAIR_CANDIDATE' if not errors else 'FAIL_EKB_PROVENANCE_REPAIR_CANDIDATE\n'+'\n'.join(errors)))
    raise SystemExit(0 if not errors else 1)
if __name__=='__main__': main()
