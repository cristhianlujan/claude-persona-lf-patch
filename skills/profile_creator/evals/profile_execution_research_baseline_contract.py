#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/'supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql'
CONTRACT=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json'
README=ROOT/'sandbox/lf_contract_gate_test/transversal_assets/profile_research_baseline_freeze/README.md'

assert MIG.is_file(), MIG
assert CONTRACT.is_file(), CONTRACT
assert README.is_file(), README
sql=MIG.read_text()
contract=json.loads(CONTRACT.read_text())
contract_sha=hashlib.sha256(CONTRACT.read_bytes()).hexdigest()

assert contract['schema_version']=='LF_PROFILE_RESEARCH_BASELINE_FREEZE_CONTRACT_V1'
assert contract['capability_code']=='PROFILE_RESEARCH_BASELINE_FREEZE'
assert contract['applicability']['authority']=='public.lf_activos.metadata.research_baseline_mode'
assert contract['applicability']['default']=='NOT_REQUIRED'
assert set(contract['applicability']['modes'])=={'NOT_REQUIRED','PRE_RESEARCH_ALWAYS'}
assert contract['applicability']['required_opt_in_contract']=='PROFILE_OUTPUT_VALIDATOR_BOUND_V1'
assert contract['baseline_contract']['canonical_digest_source']=='producer_supplied_then_required_profile_output_validator'
assert contract_sha in sql

# Generic applicability: runtime derives it from canonical asset metadata; no SRCR/profile-code case split.
assert "metadata->>'research_baseline_mode'" in sql
assert "metadata->>'research_baseline_contract'" in sql
assert 'PROFILE_RESEARCH_BASELINE_CONTRACT_INVALID' in sql
assert "mode not in ('NOT_REQUIRED','PRE_RESEARCH_ALWAYS')" in sql
assert 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' not in sql
assert 'SYSTEMIC_ROOT_CAUSE_REPAIR_LF' not in sql

# Temporal boundary is a real operation step between context admission and model execution.
assert "47,'research_baseline_freeze'" in sql
assert "step_id='context_admission'" in sql and "next_if_pass='research_baseline_freeze'" in sql
assert "'research_baseline_freeze',47,47" in sql
assert "'execute_profile'" in sql
assert sql.index("create or replace function public.lf_profile_execution_research_baseline_v1") < sql.index("insert into public.lf_operation_steps")

# Freeze binds internal-only baseline to exact input/source identities and blocks retrospective replacement.
for token in [
    'PROFILE_RESEARCH_BASELINE_INPUT_DIGEST_MISMATCH',
    'PROFILE_RESEARCH_BASELINE_SOURCE_DIGEST_MISMATCH',
    'PROFILE_RESEARCH_BASELINE_EXTERNAL_REF_FORBIDDEN',
    'PROFILE_RESEARCH_BASELINE_DIGEST_INVALID',
    "'PRE_RESEARCH_CHALLENGER'",
    "'SRCR_BASELINE_SOLUTION_V1'",
    "existing.status=step_binding.clean_result_value",
]:
    assert token in sql, token
for prefix in ['https?://','external://','web://']:
    assert prefix in sql, prefix

# Runtime freezes exact snapshot identity but deliberately does not reimplement the profile canonical digest.
assert 'p_baseline_digest text' in sql
assert "'baseline_digest',p_baseline_digest" in sql
assert "'digest_verification','PROFILE_OUTPUT_VALIDATOR_BOUND_V1'" in sql
assert "'server_snapshot_fingerprint',server_snapshot_fingerprint" in sql
assert "baseline_digest:='sha256:'" not in sql

# Execute phase is rebound to the exact persisted receipt and snapshot/digest.
for token in [
    'research_baseline_predecessor_not_clean',
    'research_baseline_execute_binding_mismatch',
    'research_baseline_output_mutated',
    "research_baseline_ref",
    "research_baseline_digest",
    "baseline_solution_snapshot",
]:
    assert token in sql, token

# Legacy/non-applicable profiles have a server-side N/A path; no baseline model payload is required.
assert "if mode='NOT_REQUIRED' then" in sql
assert "'applicability','NOT_APPLICABLE'" in sql
assert "'baseline_digest','NOT_APPLICABLE'" in sql

# No parallel table/engine/semantic authority introduced.
assert 'create table' not in sql.lower()
assert 'MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1' in sql
assert 'lf_record_operation_step_core_v1' in sql
assert 'PROFILE_RESEARCH_BASELINE_FREEZE' in sql
assert "'CAPABILITY','TRANSVERSAL_RUNTIME_ASSURANCE'" in sql

# Rollout is source/runtime-operation scoped and keeps EJECUCION_PERFIL_LF operational read-only.
assert 'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' in sql
assert "status='PRODUCCION_CONTROLADA_READ_ONLY'" in sql
assert 'PROFILE_BASELINE_POST_OPERATION_STATE_CHANGED' in sql
assert sql.strip().startswith('begin;') and sql.strip().endswith('commit;')

print('PASS_PROFILE_EXECUTION_RESEARCH_BASELINE_CONTRACT')
