#!/usr/bin/env python3
import json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
contract=json.loads((HERE/'assurance_independent_review_provider_readback_contract_v1.json').read_text())
sql=(ROOT/'supabase/migrations/20260930211500_lf_assurance_independent_review_provider_readback_v1.sql').read_text()
assert contract['function']['name']=='public.fn_lf_assurance_independent_review_provider_readback_v1'
assert contract['authority']['resolver_id']=='LF_SUPABASE_READBACK_V1'
assert contract['authority']['provider']=='SUPABASE'
assert contract['authority']['verification_method']=='SUPABASE_SQL_READBACK_PLUS_DB_DIGEST'
assert contract['required_dependency_current']==['EVIDENCE_RESOLVER_REGISTRY','EVIDENCE_LEDGER','EVIDENCE_ANTIREPLAY']
for token in [
  "capability_code='ASSURANCE_EVALUATOR'",
  "gate_code is distinct from 'ASSURANCE_INDEPENDENT_REVIEW_PROVIDER_BOUND_V1'",
  "receipt_kind is distinct from 'INDEPENDENT_REVIEW_PROVIDER_READBACK'",
  "subject_type is distinct from 'LF_TEST_JUDGE_RESULT'",
  "resolver_id is distinct from 'LF_SUPABASE_READBACK_V1'",
  "provider is distinct from 'SUPABASE'",
  "verification_method is distinct from 'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST'",
  "verification_state is distinct from 'VERIFIED'",
  "provider_readback_verified",
  "digest_recomputed",
  "receipt_payload->>'assurance_execution_id'",
  "receipt_payload->>'obligation_code'",
  "receipt_payload->>'judge_result_id'",
  "receipt_payload->>'reviewer_execution_id'",
  "receipt_payload->>'subject_revision_sha256'",
  "receipt_payload->>'source_head_sha'",
  "judge_type not in ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT')",
  "reviewer.operation_code is distinct from 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF'",
  "metadata->>'recorder' is distinct from 'lf_record_test_judge_result_v1'",
  "EVIDENCE_LEDGER",
  "EVIDENCE_ANTIREPLAY",
  "EVIDENCE_RESOLVER_REGISTRY",
]:
    assert token in sql, token
lower=sql.lower()
for forbidden in [
  'insert into private.lf_evidence_ledger_v1',
  'insert into public.lf_test_judge_results',
  'fn_lf_evidence_ledger_anchor_v1(',
  'fn_lf_capability_promote_v1(',
  'insert into public.lf_capability_current',
  "update public.lf_assurance_subject_bindings set status='active'",
]:
    assert forbidden not in lower, forbidden
assert "v_judge.judge_type not in ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT')" in sql
assert 'S36_ASSURANCE' not in sql
print('ASSURANCE_INDEPENDENT_REVIEW_PROVIDER_READBACK_V1=PASS checks=provider+digest+crossbind+no-write+no-activation')
