#!/usr/bin/env python3
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / 'supabase/migrations/20260923062500_lf_pilot_srcr_unified_execution_g02_identity_v1.sql'
SQL = MIGRATION.read_text()
LOW = SQL.lower()

REQUIRED_FIELDS = [
    'execution_id',
    'operation_code',
    'operation_spec_id',
    'operation_spec_digest',
    'profile_code',
    'profile_source_sha',
    'executor_binding_id',
    'executor_binding_digest',
]
FREEZE_FIELDS = [
    'operation_spec_id',
    'operation_spec_digest',
    'profile_code',
    'profile_source_sha',
    'executor_binding_id',
    'executor_binding_digest',
]

class G02ExecutionIdentityCandidate(unittest.TestCase):
    def test_exact_candidate_migration_exists(self):
        self.assertTrue(MIGRATION.is_file())
        self.assertIn('CANDIDATE SOURCE', SQL)
        self.assertIn('NO LIVE SUPABASE APPLY', SQL)
        self.assertNotIn('insert into supabase_migrations.schema_migrations', LOW)
        self.assertNotIn('insert into public.lf_operation_registry', LOW)

    def test_extends_existing_execution_authority(self):
        self.assertIn('alter table public.lf_operation_execution', LOW)
        self.assertNotIn('create table public.lf_operation_execution', LOW)
        self.assertIn('no parallel execution engine', LOW)

    def test_all_six_missing_identity_fields_are_typed(self):
        for field in FREEZE_FIELDS:
            self.assertRegex(LOW, rf'add column if not exists {field} text')

    def test_identity_is_all_or_none_for_legacy_compatibility(self):
        self.assertIn('lf_operation_execution_unified_identity_ck', LOW)
        for field in FREEZE_FIELDS:
            self.assertIn(f'{field} is null', LOW)
        self.assertIn("operation_spec_digest ~ '^[0-9a-f]{64}$'", LOW)
        self.assertIn("profile_source_sha ~ '^[0-9a-f]{40}$'", LOW)
        self.assertIn("executor_binding_digest ~ '^[0-9a-f]{64}$'", LOW)

    def test_v2_reservation_requires_all_eight_contract_fields(self):
        self.assertIn('fn_lf_operation_reserve_execution_v2', LOW)
        for field in REQUIRED_FIELDS:
            self.assertIn(field, LOW)
        for code in [
            'INVALID_OPERATION_SPEC_ID',
            'INVALID_OPERATION_SPEC_DIGEST',
            'INVALID_PROFILE_CODE',
            'INVALID_PROFILE_SOURCE_SHA',
            'INVALID_EXECUTOR_BINDING_ID',
            'INVALID_EXECUTOR_BINDING_DIGEST',
        ]:
            self.assertIn(code, SQL)

    def test_freeze_at_start_is_server_enforced(self):
        self.assertIn('lf_operation_execution_identity_immutable_v1', LOW)
        self.assertIn('before update of operation_spec_id, operation_spec_digest, profile_code, profile_source_sha', LOW)
        self.assertIn('executor_binding_id, executor_binding_digest', LOW)
        self.assertIn('EXECUTION_IDENTITY_IMMUTABLE', SQL)
        self.assertIn('is distinct from row(', LOW)

    def test_changed_digest_replay_is_rejected(self):
        self.assertIn('on conflict (operation_code,idempotency_key)', LOW)
        self.assertIn('EXECUTION_IDENTITY_REPLAY_MISMATCH', SQL)
        self.assertIn('v_row.operation_spec_digest', LOW)
        self.assertIn('p_operation_spec_digest', LOW)
        self.assertIn('v_row.executor_binding_digest', LOW)
        self.assertIn('p_executor_binding_digest', LOW)

    def test_existing_idempotency_and_target_guards_are_preserved(self):
        self.assertIn('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST', SQL)
        self.assertIn('IDEMPOTENCY_REPLAY_TARGET_MISMATCH', SQL)
        self.assertIn("'dispatch_permitted',v_inserted", LOW)

    def test_reservation_readback_returns_exact_identity(self):
        for field in REQUIRED_FIELDS:
            self.assertRegex(LOW, rf"'{field}'\s*,\s*v_row\.{field}")

    def test_identity_is_not_runtime_release_identity(self):
        self.assertNotIn('runtime_release_sha', LOW)
        self.assertNotIn('runtime_source_revision', LOW)

    def test_generic_sql_has_no_srcr_profile_routing_literal(self):
        self.assertNotIn('systemic_root_cause_repair_lf', LOW)
        self.assertNotIn('perfil-systemic-root-cause-repair-lf', LOW)
        self.assertNotIn('research_baseline', LOW)

    def test_privilege_surface_is_service_role_only(self):
        self.assertRegex(LOW, r'revoke all on function public\.fn_lf_operation_reserve_execution_v2\([\s\S]+?\) from public, anon, authenticated;')
        self.assertRegex(LOW, r'grant execute on function public\.fn_lf_operation_reserve_execution_v2\([\s\S]+?\) to service_role;')

if __name__ == '__main__':
    result = unittest.main(verbosity=2, exit=False).result
    print(f'PILOT_SRCR_G02_EXECUTION_IDENTITY_TESTS={result.testsRun} RESULT={"PASS" if result.wasSuccessful() else "FAIL"} LIVE_DDL_APPLIED=0')
    raise SystemExit(0 if result.wasSuccessful() else 1)
