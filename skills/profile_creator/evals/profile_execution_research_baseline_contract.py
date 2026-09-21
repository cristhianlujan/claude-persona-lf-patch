#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/'supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql'
CONTRACT=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json'
README=ROOT/'sandbox/lf_contract_gate_test/transversal_assets/profile_research_baseline_freeze/README.md'
WORKER=ROOT/'services/profile_runtime_api/scripts/hetzner_queue_worker.py'
ENGINE=ROOT/'services/profile_runtime_api/profile_runtime_api/engine.py'
LLAMA=ROOT/'services/profile_runtime_api/profile_runtime_api/llama.py'
APP=ROOT/'services/profile_runtime_api/profile_runtime_api/app.py'
MODELS=ROOT/'services/profile_runtime_api/profile_runtime_api/models.py'

for path in (MIG,CONTRACT,README,WORKER,ENGINE,LLAMA,APP,MODELS):
    assert path.is_file(), path
sql=MIG.read_text()
worker=WORKER.read_text()
engine=ENGINE.read_text()
llama=LLAMA.read_text()
app=APP.read_text()
models=MODELS.read_text()
contract=json.loads(CONTRACT.read_text())
contract_sha=hashlib.sha256(CONTRACT.read_bytes()).hexdigest()

# Canonical capability identity and server-derived applicability.
assert contract['schema_version']=='LF_PROFILE_RESEARCH_BASELINE_FREEZE_CONTRACT_V1'
assert contract['capability_code']=='PROFILE_RESEARCH_BASELINE_FREEZE'
assert contract['applicability']['default']=='NOT_REQUIRED'
assert set(contract['applicability']['modes'])=={'NOT_REQUIRED','PRE_RESEARCH_ALWAYS'}
assert contract['applicability']['required_contract_version']=='PROFILE_RESEARCH_BASELINE_BINDING_V1'
assert 'snapshot_schema' in contract['baseline_contract']['profile_asset_contract_shape']
assert contract['runtime_bridge']['consumer']=='services/profile_runtime_api/scripts/hetzner_queue_worker.py'
assert contract['dispatch_protocol']['resolver']=='public.lf_profile_execution_research_baseline_v1'
assert contract['dispatch_protocol']['not_required']=='records clean N/A step and dispatches no model'
assert contract_sha in sql
assert "metadata->>'research_baseline_mode'" in sql
assert "metadata->'research_baseline_contract'" in sql
assert "contract->>'contract_version'<>'PROFILE_RESEARCH_BASELINE_BINDING_V1'" in sql
assert "contract->>'profile_validator_binding'<>'PROFILE_OUTPUT_VALIDATOR_BOUND_V1'" in sql
assert "snapshot_binding_paths" in sql
assert "PROFILE_RESEARCH_BASELINE_SNAPSHOT_BINDING_MISMATCH" in sql
assert "source not in ('input_digest','profile_source_digest','evidence_refs','capture_stage')" in sql
assert "jsonb_typeof(value)<>'string'" in sql

# Runtime must stay profile-agnostic: profile-specific vocabulary belongs only in asset contract data.
for forbidden in (
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
    'SYSTEMIC_ROOT_CAUSE_REPAIR_LF',
    'SRCR_BASELINE_SOLUTION_V1',
    'PRE_RESEARCH_CHALLENGER',
    'leading_solution_summary',
    'known_gaps',
    'assumptions',
    'research_assurance',
    'baseline_solution_snapshot',
):
    assert forbidden not in sql, forbidden

# Deterministic-first dispatch prevents a model call on NOT_REQUIRED profiles.
assert "'public.lf_profile_execution_research_baseline_v1 + NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT'" not in sql
assert "'[]'::jsonb,'public.lf_profile_execution_research_baseline_v1'," in sql
assert "'outcome','BASELINE_REQUIRED'" in sql
assert "'recorded',false" in sql
assert "'next_action','INVOKE_SAME_PROFILE_MODEL_FOR_BASELINE_THEN_RETRY'" in sql
assert "if p_baseline_envelope is not null then" in sql
assert 'PROFILE_RESEARCH_BASELINE_UNEXPECTED_ENVELOPE' in sql

# Temporal boundary is a durable operation step before execute_profile.
assert "47,'research_baseline_freeze'" in sql
assert "step_id='context_admission'" in sql and "next_if_pass='research_baseline_freeze'" in sql
assert "'research_baseline_freeze',47,47" in sql
assert "next_if_pass='execute_profile'" in sql
assert "existing.status=step_binding.clean_result_value" in sql
assert sql.index("create or replace function public.lf_profile_execution_research_baseline_v1") < sql.index("insert into public.lf_operation_steps")

# Generic envelope binds temporal identity without duplicating profile digest semantics.
for token in (
    "p_baseline_envelope jsonb",
    "p_baseline_envelope->'snapshot'",
    "p_baseline_envelope->>'baseline_digest'",
    "p_baseline_envelope->>'capture_stage'",
    "p_baseline_envelope->>'input_digest'",
    "p_baseline_envelope->>'profile_source_digest'",
    "p_baseline_envelope->'evidence_refs'",
    "PROFILE_RESEARCH_BASELINE_ENVELOPE_INVALID",
    "PROFILE_RESEARCH_BASELINE_CAPTURE_STAGE_MISMATCH",
    "PROFILE_RESEARCH_BASELINE_INPUT_DIGEST_MISMATCH",
    "PROFILE_RESEARCH_BASELINE_SOURCE_DIGEST_MISMATCH",
    "PROFILE_RESEARCH_BASELINE_EXTERNAL_REF_FORBIDDEN",
    "'server_snapshot_fingerprint',server_snapshot_fingerprint",
):
    assert token in sql, token
for prefix in ('https?://','external://','web://'):
    assert prefix in sql, prefix
assert "btrim(ref) ~* '^(https?://|external://|web://)'" in sql
assert "baseline_digest:='sha256:'" not in sql
assert "select key,value from jsonb_each(contract->'snapshot_binding_paths')" in sql
assert "(p_baseline_envelope->'snapshot')#>binding_path is distinct from expected_bound_value" in sql

# Final binding resolves profile-owned fields via declarative JSON paths.
for token in (
    "output_snapshot_path",
    "output_digest_path",
    "jsonb_array_elements_text(contract->'output_snapshot_path')",
    "jsonb_array_elements_text(contract->'output_digest_path')",
    "output_snapshot:=(p_evidence_payload->'profile_output')#>snapshot_path",
    "output_digest:=(p_evidence_payload->'profile_output')#>>digest_path",
    "research_baseline_execute_binding_mismatch",
    "research_baseline_output_mutated",
):
    assert token in sql, token

# Legacy profiles are a server-side N/A path; no second model/engine/table is introduced.
assert "if mode='NOT_REQUIRED' then" in sql
assert "'applicability','NOT_APPLICABLE'" in sql
assert 'create table' not in sql.lower()
assert 'MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1' in sql
assert 'lf_record_operation_step_core_v1' in sql
assert "'CAPABILITY','TRANSVERSAL_RUNTIME_ASSURANCE'" in sql

# The actual Hetzner queue path must consume the same governed operation before inference.
for token in (
    'lf_profile_execution_begin_v1',
    'lf_profile_execution_context_admission_v1',
    'lf_record_profile_execution_step_v1',
    'lf_profile_execution_research_baseline_v1',
    '/v1/profile/research-baseline',
    '_begin_governed_pre_model',
    '_record_post_model_governance',
):
    assert token in worker, token
assert worker.index('_begin_governed_pre_model(conn, claimed)') < worker.index('_api_json("POST", endpoint, payload)')
assert 'def run_research_baseline' in engine
assert 'generate_research_baseline_snapshot' in llama
assert '/v1/profile/research-baseline' in app
assert 'class GovernedOperationContext' in models
assert 'class ResearchBaselineRequest' in models
assert 'governed_operation' in engine and 'governed_operation' in llama

# In-flight compatibility is explicit: old executions are bridged as N/A, required-mode inflight blocks.
assert 'PROFILE_BASELINE_PRE_REQUIRED_MODE_INFLIGHT' in sql
assert 'PROFILE_BASELINE_COMPAT_BACKFILL_INCOMPLETE' in sql
assert "coalesce(nullif(e.manifest->>'research_baseline_mode',''),'NOT_REQUIRED')='NOT_REQUIRED'" in sql
assert "v_receipt:=public.lf_profile_execution_research_baseline_v1(r.execution_id,null,v_actor)" in sql
assert "where e.operation_code='EJECUCION_PERFIL_LF'" in sql

# Rollout remains isolated to governed runtime update and preserves runtime state.
assert 'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' in sql
assert "production_apply_authorized')::boolean,false)=true" in sql
assert "status='PRODUCCION_CONTROLADA_READ_ONLY'" in sql
assert 'PROFILE_BASELINE_POST_OPERATION_STATE_CHANGED' in sql
assert 'PROFILE_BASELINE_POST_PREMODEL_RESOLVER_NOT_DETERMINISTIC' in sql
for resolver in (
    "public.lf_profile_execution_begin_v1",
    "public.lf_router_resolve_v1",
    "CANONICAL_PROFILE_ASSET_RESOLUTION",
    "EXACT_PROFILE_SOURCE_READBACK",
    "BOUND_INPUT_VALIDATION",
    "public.lf_profile_execution_context_admission_v1",
    "public.lf_profile_execution_research_baseline_v1",
    "public.lf_record_profile_execution_step_v1 + SELECTED_PROFILE_MODEL_RUNTIME",
    "BOUND_PROFILE_OUTPUT_VALIDATOR",
    "BOUND_SEMANTIC_JUDGE",
    "DETERMINISTIC_REPORT_OUTPUT",
):
    assert resolver in sql, resolver
assert sql.strip().startswith('begin;') and sql.strip().endswith('commit;')

print('PASS_PROFILE_EXECUTION_RESEARCH_BASELINE_CONTRACT')
