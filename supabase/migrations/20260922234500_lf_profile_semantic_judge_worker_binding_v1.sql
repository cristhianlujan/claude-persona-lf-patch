begin;

do $pre$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id='EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001'
      and operation_code='ACTUALIZACION_PERFIL_LF'
      and target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      and status='IN_PROGRESS'
  ) then raise exception 'PROFILE_SEMANTIC_JUDGE_GOVERNED_UPDATE_EXECUTION_MISSING'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF' and step_id='semantic_judge'
      and status='ACTIVE_ENFORCEMENT'
      and resolver_ref in ('BOUND_SEMANTIC_JUDGE','HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1')
  ) then raise exception 'PROFILE_SEMANTIC_JUDGE_BINDING_PRECONDITION_FAILED'; end if;
end
$pre$;

update public.lf_activos
set metadata=jsonb_set(
      metadata,
      '{semantic_judge_binding}',
      jsonb_build_object(
        'schema','LF_PROFILE_SEMANTIC_JUDGE_BINDING_V1',
        'prompt_path','judges/systemic_root_cause_semantic_judge.md',
        'validator_path','validators/validate_semantic_judge_result.py',
        'validator_callable','evaluate',
        'pass_verdict','PASS_INDEPENDENT_SEMANTIC',
        'candidate_input_path','profile_output',
        'scope_packet_source','INPUT_VALIDATE_SCOPE_AUTHORITY_PACKET',
        'deterministic_predecessor','output_validate',
        'independence',jsonb_build_object(
          'separate_model_call_required',true,
          'producer_prompt_reuse_forbidden',true,
          'producer_self_verdict_forbidden',true
        )
      ),
      true
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001'
where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
  and tipo_activo='PERFIL'
  and archived_at is null;

if not found then raise exception 'PROFILE_SEMANTIC_JUDGE_PROFILE_BINDING_TARGET_MISSING'; end if;

update public.lf_operation_step_contracts
set resolver_ref='HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1',
    notes='Physical consumer: services/profile_runtime_api/scripts/semantic_judge_worker.py via lf-profile-semantic-judge-worker.service. Binding is resolved from canonical public.lf_activos metadata; profile judge prompt/validator remain technical artifacts. One fresh isolated model call follows clean output_validate.',
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001'
where operation_code='EJECUCION_PERFIL_LF' and step_id='semantic_judge' and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_registry r
set source_paths=(select coalesce(jsonb_agg(d.value order by d.value),'[]'::jsonb) from (
      select distinct x.value from jsonb_array_elements_text(
        coalesce(r.source_paths,'[]'::jsonb) || jsonb_build_array(
          'services/profile_runtime_api/scripts/semantic_judge_worker.py',
          'services/profile_runtime_api/deploy/lf-profile-semantic-judge-worker.service'
        )) x(value)) d),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001'
where operation_code='EJECUCION_PERFIL_LF';

do $post$
begin
  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      and archived_at is null
      and metadata#>>'{semantic_judge_binding,schema}'='LF_PROFILE_SEMANTIC_JUDGE_BINDING_V1'
      and metadata#>>'{semantic_judge_binding,pass_verdict}'='PASS_INDEPENDENT_SEMANTIC'
      and (metadata#>>'{semantic_judge_binding,independence,separate_model_call_required}')::boolean
  ) then raise exception 'PROFILE_SEMANTIC_JUDGE_PROFILE_BINDING_READBACK_FAILED'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF' and step_id='semantic_judge'
      and resolver_ref='HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1'
      and required_evidence_keys @> '["semantic_judge_result","unsupported_claims"]'::jsonb
  ) then raise exception 'PROFILE_SEMANTIC_JUDGE_BINDING_READBACK_FAILED'; end if;
end
$post$;

commit;
