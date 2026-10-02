-- LF_ASSURANCE_INDEPENDENT_REVIEW_PROVIDER_READBACK_V1
-- Material readback adapter only. Reads canonical judge + Evidence Ledger state and returns a
-- provider-bound verification snapshot. It never writes judge/evidence rows and never decides Assurance.
-- No capability version/current promotion, subject-binding activation, runtime/deploy/production activation.

do $preflight$
declare
  v_execution_id constant text := 'EXEC-SADM-ASSURANCE-REVIEW-PROVIDER-READBACK-20260930-001';
  v_target_path constant text := 'supabase/migrations/20260930211500_lf_assurance_independent_review_provider_readback_v1.sql';
  v_count integer;
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='ASSURANCE_INDEPENDENT_REVIEW_PROVIDER_READBACK_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path=v_target_path
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.fn_lf_assurance_independent_review_provider_readback_v1(text,text,uuid,uuid,text,text,text,text)') is not null then
    raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_FUNCTION_ALREADY_EXISTS';
  end if;

  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code='ASSURANCE_EVALUATOR' and status='ACTIVE' and owner_scope='SUPER_ADMIN'
      and entry_guard_required is true and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) then
    raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_EVALUATOR_PRESTATE';
  end if;

  select count(*) into v_count from public.lf_capability_current where capability_code='ASSURANCE_EVALUATOR';
  if v_count<>0 then raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_PREMATURE_EVALUATOR_CURRENT:%',v_count; end if;
  select count(*) into v_count from public.lf_assurance_subject_bindings where status='ACTIVE';
  if v_count<>0 then raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_PREMATURE_SUBJECT_BINDING:%',v_count; end if;

  if to_regclass('private.lf_evidence_ledger_v1') is null
     or to_regclass('private.lf_evidence_resolver_registry_v1') is null
     or to_regclass('public.lf_test_judge_results') is null then
    raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_REQUIRED_SOURCE_MISSING';
  end if;
end
$preflight$;

create or replace function public.fn_lf_assurance_independent_review_provider_readback_v1(
  p_assurance_execution_id text,
  p_obligation_code text,
  p_judge_result_id uuid,
  p_evidence_receipt_id uuid,
  p_expected_reviewer_execution_id text,
  p_expected_subject_revision_sha256 text,
  p_expected_source_head_sha text,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $fn$
declare
  v_judge public.lf_test_judge_results%rowtype;
  v_reviewer public.lf_operation_execution%rowtype;
  v_receipt private.lf_evidence_ledger_v1%rowtype;
  v_subject_ref text;
  v_row_envelope jsonb;
  v_row_sha text;
  v_dependency_count integer;
begin
  if nullif(btrim(coalesce(p_assurance_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_obligation_code,'')),'') is null
     or nullif(btrim(coalesce(p_expected_reviewer_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_EXECUTION_INVALID');
  end if;

  if p_expected_subject_revision_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_source_head_sha !~ '^[0-9a-f]{40}$' then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_HASH_FORMAT');
  end if;

  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=p_assurance_execution_id and status in ('IN_PROGRESS','COMPLETED')
  ) then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_EXECUTION_INVALID');
  end if;
  if not exists (select 1 from public.lf_operation_execution where execution_id=p_actor_execution_id) then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_ACTOR_INVALID');
  end if;

  select count(*) into v_dependency_count
  from public.lf_capability_registry r
  join public.lf_capability_current c using(capability_code)
  join public.lf_capability_version_registry v
    on v.capability_code=c.capability_code and v.version=c.version and v.manifest_sha256=c.manifest_sha256
  where r.capability_code in ('EVIDENCE_RESOLVER_REGISTRY','EVIDENCE_LEDGER','EVIDENCE_ANTIREPLAY')
    and r.status='ACTIVE' and r.owner_scope='SUPER_ADMIN'
    and r.entry_guard_required is true and r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
    and v.release_state='RELEASED';
  if v_dependency_count<>3 then
    return jsonb_build_object(
      'status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_DEPENDENCY_NOT_CURRENT',
      'current_dependency_count',v_dependency_count,'required_dependency_count',3
    );
  end if;

  select * into v_judge from public.lf_test_judge_results where judge_result_id=p_judge_result_id;
  if not found then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_JUDGE_NOT_FOUND');
  end if;
  if v_judge.judge_type not in ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT') then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_TYPE_INVALID','judge_type',v_judge.judge_type);
  end if;
  if v_judge.created_by_execution_id is distinct from p_expected_reviewer_execution_id
     or v_judge.metadata->>'reviewer_execution_id' is distinct from p_expected_reviewer_execution_id
     or v_judge.metadata->>'recorder' is distinct from 'lf_record_test_judge_result_v1' then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_REVIEWER_BINDING');
  end if;

  select * into v_reviewer from public.lf_operation_execution where execution_id=p_expected_reviewer_execution_id;
  if not found or v_reviewer.operation_code is distinct from 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_REVIEWER_OPERATION');
  end if;
  if v_reviewer.status is distinct from 'COMPLETED' or v_reviewer.completed_at is null
     or v_judge.observed_at < v_reviewer.started_at or v_judge.observed_at > v_reviewer.completed_at then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_REVIEWER_STATE');
  end if;

  if v_judge.evidence_payload->>'revision_sha256' is distinct from p_expected_subject_revision_sha256 then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_REVISION_MISMATCH');
  end if;
  if jsonb_typeof(v_judge.evidence_payload->'evidence_refs') is distinct from 'array'
     or jsonb_array_length(v_judge.evidence_payload->'evidence_refs')=0 then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_EVIDENCE_REFS');
  end if;
  if nullif(btrim(coalesce(v_judge.rationale_summary,'')),'') is null then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_RATIONALE_REQUIRED');
  end if;

  v_row_envelope := jsonb_build_object(
    'judge_result_id',v_judge.judge_result_id::text,
    'test_run_id',v_judge.test_run_id::text,
    'judge_code',v_judge.judge_code,
    'judge_type',v_judge.judge_type,
    'verdict',v_judge.verdict,
    'severity',v_judge.severity,
    'findings',v_judge.findings,
    'evidence_payload',v_judge.evidence_payload,
    'rationale_summary',v_judge.rationale_summary,
    'observed_at',to_char(v_judge.observed_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'metadata',v_judge.metadata,
    'created_by_execution_id',v_judge.created_by_execution_id
  );
  v_row_sha := encode(extensions.digest(convert_to(v_row_envelope::text,'UTF8'),'sha256'),'hex');
  v_subject_ref := 'supabase://public/lf_test_judge_results/'||p_judge_result_id::text;

  select * into v_receipt from private.lf_evidence_ledger_v1 where receipt_id=p_evidence_receipt_id;
  if not found then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_LEDGER_NOT_FOUND');
  end if;

  if v_receipt.execution_id is distinct from p_assurance_execution_id
     or v_receipt.capability_code is distinct from 'ASSURANCE_EVALUATOR'
     or v_receipt.gate_code is distinct from 'ASSURANCE_INDEPENDENT_REVIEW_PROVIDER_BOUND_V1'
     or v_receipt.receipt_kind is distinct from 'INDEPENDENT_REVIEW_PROVIDER_READBACK'
     or v_receipt.subject_type is distinct from 'LF_TEST_JUDGE_RESULT'
     or v_receipt.subject_ref is distinct from v_subject_ref
     or v_receipt.subject_sha256 is distinct from v_row_sha
     or v_receipt.source_head_sha is distinct from p_expected_source_head_sha
     or v_receipt.authority_ref is distinct from 'public.lf_test_judge_results'
     or v_receipt.provider_ref is distinct from v_subject_ref then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_LEDGER_BINDING');
  end if;

  if v_receipt.resolver_id is distinct from 'LF_SUPABASE_READBACK_V1'
     or v_receipt.provider is distinct from 'SUPABASE'
     or v_receipt.verification_method is distinct from 'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST'
     or v_receipt.verification_state is distinct from 'VERIFIED'
     or v_receipt.verification_payload->'provider_readback_verified' is distinct from 'true'::jsonb
     or v_receipt.verification_payload->'digest_recomputed' is distinct from 'true'::jsonb then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_LEDGER_VERIFICATION');
  end if;

  if v_receipt.receipt_payload->>'assurance_execution_id' is distinct from p_assurance_execution_id
     or v_receipt.receipt_payload->>'obligation_code' is distinct from p_obligation_code
     or v_receipt.receipt_payload->>'judge_result_id' is distinct from p_judge_result_id::text
     or v_receipt.receipt_payload->>'reviewer_execution_id' is distinct from p_expected_reviewer_execution_id
     or v_receipt.receipt_payload->>'subject_revision_sha256' is distinct from p_expected_subject_revision_sha256
     or v_receipt.receipt_payload->>'source_head_sha' is distinct from p_expected_source_head_sha then
    return jsonb_build_object('status','BLOCKED','code','BLOCK_ASSURANCE_REVIEW_PROVIDER_LEDGER_PAYLOAD_BINDING');
  end if;

  return jsonb_build_object(
    'schema_version','lf-assurance-independent-review-provider-readback-result/v1',
    'status','VERIFIED_PROVIDER_BOUND',
    'material_adapter','public.fn_lf_assurance_independent_review_provider_readback_v1',
    'assurance_execution_id',p_assurance_execution_id,
    'obligation_code',p_obligation_code,
    'judge_result_id',p_judge_result_id::text,
    'judge_type',v_judge.judge_type,
    'judge_verdict',v_judge.verdict,
    'reviewer_execution_id',p_expected_reviewer_execution_id,
    'subject_revision_sha256',p_expected_subject_revision_sha256,
    'source_head_sha',p_expected_source_head_sha,
    'db_row_sha256',v_row_sha,
    'evidence_receipt_id',v_receipt.receipt_id::text,
    'evidence_receipt_sha256',v_receipt.receipt_sha256,
    'resolver_id',v_receipt.resolver_id,
    'provider',v_receipt.provider,
    'verification_method',v_receipt.verification_method,
    'verification_state',v_receipt.verification_state,
    'provider_readback_verified',true,
    'digest_recomputed',true,
    'evidence_ref','evidence-ledger://'||v_receipt.receipt_id::text,
    'durable',true
  );
end
$fn$;

revoke all on function public.fn_lf_assurance_independent_review_provider_readback_v1(text,text,uuid,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.fn_lf_assurance_independent_review_provider_readback_v1(text,text,uuid,uuid,text,text,text,text) to service_role;

do $inventory$
declare
  v_execution_id constant text := 'EXEC-SADM-ASSURANCE-REVIEW-PROVIDER-READBACK-20260930-001';
  v_target_path constant text := 'supabase/migrations/20260930211500_lf_assurance_independent_review_provider_readback_v1.sql';
  v_batch uuid := gen_random_uuid();
  v_contract_ref constant text := 'sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_independent_review_provider_readback_contract_v1.json';
begin
  update public.lf_activos
  set metadata = jsonb_set(
        metadata,
        '{provider_bound_review_adapter}',
        jsonb_build_object(
          'schema_version','lf-assurance-independent-review-provider-readback-contract/v1',
          'function','public.fn_lf_assurance_independent_review_provider_readback_v1',
          'signature','public.fn_lf_assurance_independent_review_provider_readback_v1(text,text,uuid,uuid,text,text,text,text)',
          'contract_ref',v_contract_ref,
          'resolver_id','LF_SUPABASE_READBACK_V1',
          'provider','SUPABASE',
          'verification_method','SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
          'requires_current',jsonb_build_array('EVIDENCE_RESOLVER_REGISTRY','EVIDENCE_LEDGER','EVIDENCE_ANTIREPLAY'),
          'writes_evidence',false,
          'writes_judge',false,
          'material_assurance_decision',false
        ),true
      ),
      updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  where codigo_activo='ASSURANCE_EVALUATOR' and archived_at is null;
  if not found then raise exception 'BLOCK_ASSURANCE_REVIEW_PROVIDER_ASSET_MISSING'; end if;

  if not exists (select 1 from public.lf_activo_relaciones where codigo_activo='ASSURANCE_EVALUATOR' and relacionado_codigo='EVIDENCE_RESOLVER_REGISTRY' and relacion_tipo='DEPENDE_DE') then
    insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id)
    values('ASSURANCE_EVALUATOR','EVIDENCE_RESOLVER_REGISTRY','DEPENDE_DE','PROVIDER_IDENTITY_AUTHORITY',v_target_path,v_batch,v_execution_id,v_execution_id);
  end if;
  if not exists (select 1 from public.lf_activo_relaciones where codigo_activo='ASSURANCE_EVALUATOR' and relacionado_codigo='EVIDENCE_LEDGER' and relacion_tipo='DEPENDE_DE') then
    insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id)
    values('ASSURANCE_EVALUATOR','EVIDENCE_LEDGER','DEPENDE_DE','VERIFIED_PROVIDER_BOUND_RECEIPT',v_target_path,v_batch,v_execution_id,v_execution_id);
  end if;
  if not exists (select 1 from public.lf_activo_relaciones where codigo_activo='ASSURANCE_EVALUATOR' and relacionado_codigo='EVIDENCE_ANTIREPLAY' and relacion_tipo='DEPENDE_DE') then
    insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id)
    values('ASSURANCE_EVALUATOR','EVIDENCE_ANTIREPLAY','DEPENDE_DE','RECEIPT_CROSSBIND_AND_REPLAY_GUARD',v_target_path,v_batch,v_execution_id,v_execution_id);
  end if;
end
$inventory$;

comment on function public.fn_lf_assurance_independent_review_provider_readback_v1(text,text,uuid,uuid,text,text,text,text) is
'Assurance material readback adapter. Requires current governed evidence-plane dependencies, recomputes the canonical judge-row digest in Supabase, cross-binds a VERIFIED LF_SUPABASE_READBACK_V1 Evidence Ledger receipt to the exact Assurance execution/obligation/judge/reviewer/revision/source head, and returns verification only. It does not write evidence or decide Assurance.';
