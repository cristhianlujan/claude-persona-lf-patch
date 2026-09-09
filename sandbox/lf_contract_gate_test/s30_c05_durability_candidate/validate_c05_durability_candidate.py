#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import yaml

REQUIRED_TOP={
 'version','status','source_strategy','purpose','authority','currentness',
 'minimal_extension_candidate','idempotency_contract','lease_contract',
 'checkpoint_contract','retry_contract','preexecution_sequence','hard_guards',
 'rollback_only_schema_canary_required','required_after_canary','claim_ceiling','promotion_rule'
}
REQUIRED_FIELDS={
 'idempotency_key':'text','lease_owner':'text','lease_expires_at':'timestamptz'
}
REQUIRED_GUARDS={
 'NO_DDL_BEFORE_SCHEMA_AUTHORITY',
 'NO_REUSE_SPECIALIZED_CHECKOUT_IDEMPOTENCY_WITHOUT_COMPATIBILITY_PROOF',
 'NO_DUPLICATE_IRREVERSIBLE_EFFECT_FOR_SAME_IDEMPOTENCY_KEY',
 'NO_LEASE_TAKEOVER_BEFORE_EXPIRY',
 'NO_MATERIAL_WORK_BEFORE_DURABLE_START_READBACK',
 'NO_CLOSE_BEFORE_CHECKPOINT_AND_EVIDENCE_PERSIST',
 'NO_SCHEDULER_AS_STATE_AUTHORITY',
 'NO_BLIND_RETRY_OF_CONTRACT_OR_SEMANTIC_FAILURE',
 'NO_SAME_STATEMENT_READBACK_AS_CLOSURE_EVIDENCE',
 'BLOCK_ON_CRITICAL_AUTHORITY_MISSING',
 'NO_AUTOMATIC_RUNTIME_ENABLE',
 'NO_AUTOMATIC_PRODUCTION_PROMOTION'
}
EXPECTED_SEQUENCE=[
 'ROUTER','EKB_APPLICABLE','DATA_ACCESS_BINDINGS','SCHEMA_CONTRACT',
 'OPERATION_CONTRACTS','ALL_INTENDED_STEPS','JUDGES_AND_RESULT_VOCABULARY',
 'DEPENDENCIES_AND_IMPORT_CLOSURE','CI_PATHS_AND_RUNNER_WIRING',
 'PERMISSIONS_SECRETS_AND_READBACK','EVIDENCE_PROVIDER_AND_RESOLVER',
 'EXPECTED_OUTPUT_CONTRACT','ONLY_THEN_MATERIAL_WORK'
]


def load(path):
 data=yaml.safe_load(Path(path).read_text(encoding='utf-8'))
 if not isinstance(data,dict): raise ValueError('CONTRACT_OBJECT_REQUIRED')
 return data


def validate(data):
 errors=[]
 missing=sorted(REQUIRED_TOP-set(data))
 if missing:
  return ['TOP_KEYS_MISSING:'+','.join(missing)]
 if data.get('status')!='CANDIDATO_READ_ONLY': errors.append('STATUS_CEILING_MISMATCH')
 auth=data.get('authority') or {}
 if auth.get('router')!='ACT-0001': errors.append('ROUTER_AUTHORITY_MISMATCH')
 if auth.get('schema_authority_required_before_ddl') is not True: errors.append('SCHEMA_AUTHORITY_GATE_MISSING')
 if auth.get('critical_authority_missing_blocks') is not True: errors.append('CRITICAL_AUTHORITY_MUST_BLOCK')
 cur=data.get('currentness') or {}
 if cur.get('generic_idempotency_present') is not False: errors.append('CURRENTNESS_IDEMPOTENCY_MISMATCH')
 if cur.get('generic_lease_present') is not False: errors.append('CURRENTNESS_LEASE_MISMATCH')
 if cur.get('specialized_carrier_reuse_allowed') is not False: errors.append('SPECIALIZED_REUSE_MUST_REMAIN_BLOCKED')
 ext=data.get('minimal_extension_candidate') or {}
 if ext.get('target_table')!='public.lf_operation_execution': errors.append('TARGET_TABLE_MISMATCH')
 if ext.get('new_table_default') is not False: errors.append('NEW_TABLE_DEFAULT_FORBIDDEN')
 actual={f.get('name'):f.get('type') for f in ext.get('fields') or [] if isinstance(f,dict)}
 if actual!=REQUIRED_FIELDS: errors.append('MINIMAL_FIELDS_MISMATCH')
 cp=ext.get('checkpoint') or {}
 if cp.get('storage')!='manifest' or cp.get('typed_column_required_now') is not False: errors.append('CHECKPOINT_MINIMALITY_MISMATCH')
 idem=data.get('idempotency_contract') or {}
 if idem.get('same_key_duplicate_irreversible_effect_allowed') is not False: errors.append('DUPLICATE_EFFECT_MUST_BE_FORBIDDEN')
 if idem.get('same_key_same_logical_effect') is not True: errors.append('SAME_KEY_IDENTITY_REQUIRED')
 lease=data.get('lease_contract') or {}
 if lease.get('takeover_before_expiry_allowed') is not False: errors.append('EARLY_LEASE_TAKEOVER_FORBIDDEN')
 if lease.get('takeover_after_expiry_allowed') is not True: errors.append('EXPIRED_LEASE_TAKEOVER_REQUIRED')
 checkpoint=data.get('checkpoint_contract') or {}
 if checkpoint.get('durable_start_before_material_work') is not True: errors.append('DURABLE_START_REQUIRED')
 if checkpoint.get('scheduler_is_not_state_authority') is not True: errors.append('SCHEDULER_AUTHORITY_FORBIDDEN')
 retry=data.get('retry_contract') or {}
 if retry.get('contract_or_semantic_failure_auto_retry') is not False: errors.append('SEMANTIC_AUTO_RETRY_FORBIDDEN')
 if retry.get('safe_replay_reuses_same_idempotency_key') is not True: errors.append('SAFE_REPLAY_KEY_REQUIRED')
 if data.get('preexecution_sequence')!=EXPECTED_SEQUENCE: errors.append('PREEXECUTION_SEQUENCE_MISMATCH')
 guards=set(data.get('hard_guards') or [])
 missing_guards=sorted(REQUIRED_GUARDS-guards)
 if missing_guards: errors.append('HARD_GUARDS_MISSING:'+','.join(missing_guards))
 canary=set(data.get('rollback_only_schema_canary_required') or [])
 for req in {'SAME_KEY_DUPLICATE_NEGATIVE','LEASE_CONTENTION_NEGATIVE','EXPIRED_LEASE_TAKEOVER_POSITIVE','ROLLBACK'}:
  if req not in canary: errors.append('CANARY_REQUIREMENT_MISSING:'+req)
 after=set(data.get('required_after_canary') or [])
 for req in {'independent_schema_readback','zero_durable_schema_change','zero_durable_execution_residue','exact_head_ci_success'}:
  if req not in after: errors.append('POST_CANARY_EVIDENCE_MISSING:'+req)
 ceiling=str(data.get('claim_ceiling') or '')
 for forbidden in ('NO_DDL','NO_ROUTER','NO_RUNTIME','NO_PRODUCTION'):
  if forbidden not in ceiling: errors.append('CLAIM_CEILING_INCOMPLETE:'+forbidden)
 return errors


def main():
 p=argparse.ArgumentParser();p.add_argument('contract');p.add_argument('--json',action='store_true');a=p.parse_args()
 errors=validate(load(a.contract));result={'valid':not errors,'blocking_codes':errors}
 print(json.dumps(result,sort_keys=True) if a.json else ('PASS_S30_C05_DURABILITY_CANDIDATE' if not errors else 'FAIL_S30_C05_DURABILITY_CANDIDATE'))
 if not a.json:
  for e in errors: print(e)
 raise SystemExit(0 if not errors else 1)

if __name__=='__main__': main()
