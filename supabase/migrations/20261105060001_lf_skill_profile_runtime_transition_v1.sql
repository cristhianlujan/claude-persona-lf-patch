-- lf_skill_profile_runtime_transition_v1
-- Registers skill PROFILE_RUNTIME_TRANSITION in the existing skill invoker so the profile route
-- (issue lf-profile-resume-governed -> OIDC -> Edge -> lf_skill_invoke_v1) can run the governed
-- NO_HABILITADO -> CANDIDATE_READ_ONLY transition added by 20261105060000. No new Edge action,
-- no new dispatcher, no new credential. Only the Reparador is authorised (owner chat conformity, 2026-11-05).

-- Handler: read-only precheck. Never writes; reports whether the exact source state is present.
create or replace function public.lf_skill_h_profile_runtime_transition_propose_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_code text := p_input->>'profile_code';
  r public.lf_activos%rowtype;
  v_n integer;
begin
  if v_code is null or v_code !~ '^PERFIL-[A-Z0-9][A-Z0-9-]{2,100}$' then
    return jsonb_build_object('status', 'BLOCKED', 'blocking_code', 'TRANSITION_PROFILE_CODE_INVALID');
  end if;
  select count(*) into v_n from public.lf_activos
   where tipo_activo = 'PERFIL' and codigo_activo = v_code and archived_at is null;
  if v_n <> 1 then
    return jsonb_build_object('status', 'BLOCKED', 'blocking_code', 'TRANSITION_PROFILE_NOT_UNIQUE', 'matches', v_n);
  end if;
  select * into r from public.lf_activos
   where tipo_activo = 'PERFIL' and codigo_activo = v_code and archived_at is null;
  return jsonb_build_object(
    'status', 'PRECHECK_ONLY',
    'profile_code', v_code,
    'source_state_exact',
      (r.estado_original = 'CANDIDATE_READ_ONLY' and r.estado_documental = 'CANDIDATO'
       and r.estado_operativo = 'READ_ONLY' and r.nivel_control = 'PROFILE_REGISTRY'
       and r.runtime_estado = 'NO_HABILITADO' and r.impacto_automatico = 'BLOQUEADO'),
    'current_runtime_estado', r.runtime_estado,
    'target_runtime_estado', 'CANDIDATE_READ_ONLY',
    'writes', false);
end;
$fn$;

-- Opener: performs the transition (raises TRANSITION_* codes on any block, which rolls back the
-- whole invocation) and records the child execution of the governed operation.
create or replace function public.lf_skill_o_profile_runtime_transition_v1(
  p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_result jsonb;
begin
  v_result := public.lf_profile_runtime_transition_v1(jsonb_build_object(
    'profile_code', p_input->>'profile_code',
    'requested_by', p_input->>'requested_by',
    'request_ref', p_input->>'request_ref',
    'owner_authorization', p_input->'owner_authorization'));

  insert into public.lf_operation_execution
    (execution_id, operation_code, target_type, target_code, manifest, request_sha256, idempotency_key, created_by_execution_id)
  values
    (p_child, 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF', 'PERFIL', p_input->>'profile_code',
     jsonb_build_object('profile_handoff', jsonb_build_object('source_execution_id', p_parent, 'skill_run_id', p_run,
                                                            'via', 'SKILL_INVOKER'),
                        'transition_result', v_result,
                        'contract', 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v1.2',
                        'no_production', true, 'no_github_write', true),
     p_request_sha, 'skill-child-v1:' || p_run, p_parent);

  -- Close the child when the status machine allows it; otherwise leave it visible as IN_PROGRESS
  -- (the transition itself is already persisted and receipted).
  begin
    update public.lf_operation_execution set status = 'COMPLETED' where execution_id = p_child;
  exception when others then
    null;
  end;
end;
$fn$;

revoke all on function public.lf_skill_h_profile_runtime_transition_propose_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_skill_o_profile_runtime_transition_v1(text, jsonb, text, text, text) from public, anon, authenticated;
grant execute on function public.lf_skill_h_profile_runtime_transition_propose_v1(jsonb) to service_role;
grant execute on function public.lf_skill_o_profile_runtime_transition_v1(text, jsonb, text, text, text) to service_role;

insert into public.lf_skill_catalog_v1
  (skill_code, description, required_operation, handler_fn, effect, input_required, status, opener_fn)
values
  ('PROFILE_RUNTIME_TRANSITION',
   'Transicion unica y acotada de un perfil NO_HABILITADO a CANDIDATE_READ_ONLY (solo lectura, impacto BLOQUEADO) por TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF contrato v1.2. Requiere la frase de conformidad del dueno.',
   'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',
   'lf_skill_h_profile_runtime_transition_propose_v1',
   'WRITE_GOVERNED',
   array['profile_code','requested_by','request_ref','owner_authorization'],
   'READY',
   'lf_skill_o_profile_runtime_transition_v1')
on conflict (skill_code) do nothing;

insert into public.lf_profile_write_authority_v1 (profile_code, operation_code, status, basis, self_update_allowed)
values ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF', 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF', 'ACTIVE',
        'aprobado por usuario 2026-11-05 (chat): ruta gobernada de transicion a solo lectura para Claude y GPT, via Reparador', false)
on conflict (profile_code, operation_code) do nothing;
