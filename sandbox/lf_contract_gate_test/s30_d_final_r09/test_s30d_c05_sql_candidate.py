#!/usr/bin/env python3
import json,re,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent
SQL=(HERE/'c05_generic_execution_reliability_candidate_v1.sql').read_text()
class T(unittest.TestCase):
 def test_candidate_is_not_canonical_migration(self):
  self.assertIn('CANDIDATE ONLY',SQL); self.assertNotIn('insert into public.lf_operation_registry',SQL.lower())
 def test_additive_typed_carriers(self):
  for x in ['idempotency_key text','request_sha256 text','lease_owner text','lease_expires_at timestamptz','lease_fence bigint','checkpoint_seq bigint','checkpoint_payload jsonb']: self.assertIn(x,SQL)
 def test_idempotency_unique_and_hash_guard(self):
  self.assertIn('lf_operation_execution_idempotency_uq',SQL); self.assertIn("request_sha256 ~ '^[0-9a-f]{64}$'",SQL)
 def test_reservation_fail_closed(self):
  self.assertIn('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST',SQL); self.assertIn('IDEMPOTENCY_REPLAY_TARGET_MISMATCH',SQL); self.assertIn("'dispatch_permitted',v_inserted",SQL)
 def test_lease_has_fencing_and_expiry(self):
  self.assertIn('lease_fence+1',SQL); self.assertIn('LEASE_HELD',SQL); self.assertIn('STALE_OR_MISSING_LEASE_FENCE',SQL)
 def test_checkpoint_is_monotonic_and_fenced(self):
  self.assertIn('CHECKPOINT_NON_MONOTONIC',SQL); self.assertIn('CHECKPOINT_SEQ_REUSED_WITH_DIFFERENT_PAYLOAD',SQL); self.assertIn('for update',SQL.lower())
 def test_effect_response_loss_never_auto_redispatches(self):
  self.assertIn('RECONCILIATION_REQUIRED',SQL); self.assertIn("'dispatch_permitted',false",SQL); self.assertIn('EFFECT_RESERVED_NEW',SQL)
 def test_effect_table_is_private(self):
  self.assertIn('revoke all on public.lf_operation_effect_guard from public, anon, authenticated',SQL.lower()); self.assertIn('to service_role',SQL.lower())
 def test_functions_not_exposed_to_authenticated(self):
  for fn in ['reserve_execution','acquire_lease','checkpoint','reserve_effect','mark_effect_succeeded','release_lease']:
   self.assertRegex(SQL.lower(),rf'revoke all on function public\.fn_lf_operation_{fn}_v1\([^;]+\) from public, anon, authenticated;')
 def test_no_operation_bootstrap_or_scheduler(self):
  low=SQL.lower(); self.assertNotIn('ejecucion_estrategia_lf',low); self.assertNotIn('orquestacion_estrategias_lf',low); self.assertNotIn('scheduler',low)
if __name__=='__main__':
 r=unittest.main(verbosity=2,exit=False).result
 print(f'S30_C05_SQL_CANDIDATE_TESTS={r.testsRun} RESULT={"PASS" if r.wasSuccessful() else "FAIL"} DDL_APPLIED=0')
 raise SystemExit(0 if r.wasSuccessful() else 1)
