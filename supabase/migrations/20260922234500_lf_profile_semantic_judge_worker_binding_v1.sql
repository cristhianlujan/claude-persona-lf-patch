begin;

-- Physical resolver binding only. Semantic authority remains the profile-bound
-- judge contract; this migration does not create a second judge or lifecycle.
do $pre$
begin
  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='semantic_judge'
      and status='ACTIVE_ENFORCEMENT'
      and resolver_ref in ('BOUND_SEMANTIC_JUDGE','HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1')
  ) then
    raise exception 'PROFILE_SEMANTIC_JUDGE_BINDING_PRECONDITION_FAILED';
  end if;

  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='report_output'
      and status='ACTIVE_ENFORCEMENT'
      and resolver_ref='DETERMINISTIC_REPORT_OUTPUT'
  ) then
    raise exception 'PROFILE_REPORT_OUTPUT_BINDING_PRECONDITION_FAILED';
  end if;
end
$pre$;

update public.lf_operation_step_contracts
set resolver_ref='HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1',
    notes='Physical consumer: services/profile_runtime_api/scripts/semantic_judge_worker.py via lf-profile-semantic-judge-worker.service. The worker executes one fresh isolated model call after clean output_validate, loads the profile semantic_judge_binding.json, validates the independent receipt deterministically, and records through lf_record_profile_execution_step_v1. Supabase remains operational authority; profile judge contract remains semantic authority.',
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-PROFILE-SEMANTIC-JUDGE-WIRING-20260922-001'
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='semantic_judge'
  and status='ACTIVE_ENFORCEMENT';

-- Bind the operation inventory to the implementation artifacts without making
-- GitHub an operational authority. source_paths is canonical JSONB.
update public.lf_operation_registry r
set source_paths=(
      select coalesce(jsonb_agg(d.value order by d.value), '[]'::jsonb)
      from (
        select distinct x.value
        from jsonb_array_elements_text(
          coalesce(r.source_paths, '[]'::jsonb)
          || jsonb_build_array(
            'services/profile_runtime_api/scripts/semantic_judge_worker.py',
            'services/profile_runtime_api/deploy/lf-profile-semantic-judge-worker.service',
            'profiles/*/contracts/semantic_judge_binding.json'
          )
        ) as x(value)
      ) as d
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-PROFILE-SEMANTIC-JUDGE-WIRING-20260922-001'
where operation_code='EJECUCION_PERFIL_LF';

do $post$
begin
  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='semantic_judge'
      and resolver_ref='HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1'
      and required_evidence_keys @> '["semantic_judge_result","unsupported_claims"]'::jsonb
  ) then
    raise exception 'PROFILE_SEMANTIC_JUDGE_BINDING_READBACK_FAILED';
  end if;

  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF'
      and source_paths @> jsonb_build_array(
        'services/profile_runtime_api/scripts/semantic_judge_worker.py',
        'services/profile_runtime_api/deploy/lf-profile-semantic-judge-worker.service',
        'profiles/*/contracts/semantic_judge_binding.json'
      )
  ) then
    raise exception 'PROFILE_SEMANTIC_JUDGE_SOURCE_PATH_READBACK_FAILED';
  end if;
end
$post$;

commit;
