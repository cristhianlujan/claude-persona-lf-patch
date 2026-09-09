#!/usr/bin/env python3
import copy
from pathlib import Path
import yaml
from validate_c05_durability_candidate import validate

ROOT=Path(__file__).resolve().parent
BASE=yaml.safe_load((ROOT/'c05_durability_contract.yaml').read_text(encoding='utf-8'))

def run_case(name,mutator,expect_valid):
 data=copy.deepcopy(BASE);mutator(data);errors=validate(data);actual=not errors
 if actual!=expect_valid:
  raise AssertionError(f'{name}: expected valid={expect_valid}, got valid={actual}, errors={errors}')
 print(f'PASS {name}: valid={actual}')

def noop(_): pass

def main():
 cases=[
  ('base',noop,True),
  ('ddl_without_authority',lambda d:d['authority'].__setitem__('schema_authority_required_before_ddl',False),False),
  ('critical_authority_not_blocking',lambda d:d['authority'].__setitem__('critical_authority_missing_blocks',False),False),
  ('reuse_checkout_specialized_carrier',lambda d:d['currentness'].__setitem__('specialized_carrier_reuse_allowed',True),False),
  ('new_table_default',lambda d:d['minimal_extension_candidate'].__setitem__('new_table_default',True),False),
  ('duplicate_effect_allowed',lambda d:d['idempotency_contract'].__setitem__('same_key_duplicate_irreversible_effect_allowed',True),False),
  ('lease_takeover_early',lambda d:d['lease_contract'].__setitem__('takeover_before_expiry_allowed',True),False),
  ('no_durable_start',lambda d:d['checkpoint_contract'].__setitem__('durable_start_before_material_work',False),False),
  ('semantic_auto_retry',lambda d:d['retry_contract'].__setitem__('contract_or_semantic_failure_auto_retry',True),False),
  ('scheduler_as_state_authority',lambda d:d['checkpoint_contract'].__setitem__('scheduler_is_not_state_authority',False),False),
  ('preexecution_reordered',lambda d:d['preexecution_sequence'].__setitem__(0,'EKB_APPLICABLE'),False),
  ('missing_rollback',lambda d:d['rollback_only_schema_canary_required'].remove('ROLLBACK'),False),
 ]
 for name,mutator,expect in cases: run_case(name,mutator,expect)
 print(f'S30_C05_DURABILITY_REGRESSIONS_PASS={len(cases)}/{len(cases)}')

if __name__=='__main__': main()
