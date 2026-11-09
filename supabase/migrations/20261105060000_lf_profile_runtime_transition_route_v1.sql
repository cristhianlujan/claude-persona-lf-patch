-- lf_profile_runtime_transition_route_v1
-- Governed, persistent route for TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF (contract v1.2).
-- Only transition allowed: NO_HABILITADO -> CANDIDATE_READ_ONLY (read-only candidate, impact BLOQUEADO).
-- Not production, not R4, no GitHub write. Callable only by service_role (Edge).
-- Owner conformity (chat) is carried as a literal statement and stored in the receipt; its authorship
-- cannot be verified by the database, so the function is hard-bounded instead.

create table if not exists public.lf_profile_runtime_transition_receipt_v1 (
  receipt_id bigint generated always as identity primary key,
  profile_code text not null,
  from_state jsonb not null,
  to_state jsonb not null,
  from_state_sha256 text not null,
  owner_authorization jsonb not null,
  requested_by text not null,
  request_ref text not null,
  created_at timestamptz not null default now(),
  constraint lf_profile_runtime_transition_receipt_one_shot unique (profile_code, from_state_sha256)
);
alter table public.lf_profile_runtime_transition_receipt_v1 enable row level security;
revoke all on table public.lf_profile_runtime_transition_receipt_v1 from public, anon, authenticated;

create or replace function public.lf_profile_runtime_transition_v1(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_keys text[];
  v_code text;
  v_by text;
  v_ref text;
  v_auth jsonb;
  v_at timestamptz;
  v_n integer;
  r public.lf_activos%rowtype;
  a public.lf_activos%rowtype;
  v_from jsonb;
  v_to jsonb;
  v_hash text;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'TRANSITION_REQUEST_SHAPE_INVALID';
  end if;
  select array_agg(k order by k) into v_keys from jsonb_object_keys(p_request) k;
  if v_keys is distinct from array['owner_authorization','profile_code','request_ref','requested_by'] then
    raise exception 'TRANSITION_REQUEST_SHAPE_INVALID';
  end if;
  v_code := p_request->>'profile_code';
  v_by := p_request->>'requested_by';
  v_ref := p_request->>'request_ref';
  v_auth := p_request->'owner_authorization';
  if v_code is null or v_code !~ '^PERFIL-[A-Z0-9][A-Z0-9-]{2,100}$' then
    raise exception 'TRANSITION_PROFILE_CODE_INVALID';
  end if;
  if v_by is null or v_by not in ('claude','gpt','owner') then
    raise exception 'TRANSITION_REQUESTER_INVALID';
  end if;
  if v_ref is null or v_ref !~ '^https://github\.com/cristhianlujan/claude-persona-lf-patch/issues/[0-9]+$' then
    raise exception 'TRANSITION_REQUEST_REF_INVALID';
  end if;
  if jsonb_typeof(v_auth) <> 'object' then
    raise exception 'TRANSITION_AUTHORIZATION_INVALID';
  end if;
  select array_agg(k order by k) into v_keys from jsonb_object_keys(v_auth) k;
  if v_keys is distinct from array['authorized_at','mode','profile_code','statement']
     or v_auth->>'mode' <> 'OWNER_CHAT_CONFORMITY_ONE_SHOT'
     or v_auth->>'profile_code' is distinct from v_code
     or jsonb_typeof(v_auth->'statement') <> 'string'
     or char_length(v_auth->>'statement') not between 12 and 1000 then
    raise exception 'TRANSITION_AUTHORIZATION_INVALID';
  end if;
  begin
    v_at := (v_auth->>'authorized_at')::timestamptz;
  exception when others then
    raise exception 'TRANSITION_AUTHORIZATION_INVALID';
  end;
  if v_at > now() + interval '5 minutes' or v_at < now() - interval '72 hours' then
    raise exception 'TRANSITION_AUTHORIZATION_EXPIRED_OR_FUTURE';
  end if;

  select count(*) into v_n from public.lf_activos
   where tipo_activo = 'PERFIL' and codigo_activo = v_code and archived_at is null;
  if v_n <> 1 then
    raise exception 'TRANSITION_PROFILE_NOT_UNIQUE:%', v_n;
  end if;
  select * into r from public.lf_activos
   where tipo_activo = 'PERFIL' and codigo_activo = v_code and archived_at is null for update;

  if r.estado_original is distinct from 'CANDIDATE_READ_ONLY'
     or r.estado_documental is distinct from 'CANDIDATO'
     or r.estado_operativo is distinct from 'READ_ONLY'
     or r.nivel_control is distinct from 'PROFILE_REGISTRY'
     or r.runtime_estado is distinct from 'NO_HABILITADO'
     or r.impacto_automatico is distinct from 'BLOQUEADO' then
    raise exception 'TRANSITION_SOURCE_STATE_DRIFT';
  end if;

  select count(*) into v_n from public.cat_estado_normalizacion_lf
   where estado_original = 'CANDIDATO_CONTROLADO_READ_ONLY' and estado_documental = 'CANDIDATO'
     and estado_operativo = 'READ_ONLY' and nivel_control = 'CONTROLADO'
     and runtime_estado = 'CANDIDATE_READ_ONLY' and impacto_automatico = 'BLOQUEADO';
  if v_n <> 1 then
    raise exception 'TRANSITION_TARGET_STATE_UNREGISTERED';
  end if;

  v_from := jsonb_build_object('estado_original', r.estado_original, 'estado_documental', r.estado_documental,
    'estado_operativo', r.estado_operativo, 'nivel_control', r.nivel_control,
    'runtime_estado', r.runtime_estado, 'impacto_automatico', r.impacto_automatico);
  v_to := jsonb_build_object('estado_original', 'CANDIDATO_CONTROLADO_READ_ONLY', 'estado_documental', 'CANDIDATO',
    'estado_operativo', 'READ_ONLY', 'nivel_control', 'CONTROLADO',
    'runtime_estado', 'CANDIDATE_READ_ONLY', 'impacto_automatico', 'BLOQUEADO');
  v_hash := encode(sha256(convert_to(v_from::text, 'UTF8')), 'hex');

  begin
    insert into public.lf_profile_runtime_transition_receipt_v1
      (profile_code, from_state, to_state, from_state_sha256, owner_authorization, requested_by, request_ref)
    values (v_code, v_from, v_to, v_hash, v_auth, v_by, v_ref);
  exception when unique_violation then
    raise exception 'TRANSITION_ALREADY_USED';
  end;

  update public.lf_activos
     set estado_original = 'CANDIDATO_CONTROLADO_READ_ONLY',
         nivel_control = 'CONTROLADO',
         runtime_estado = 'CANDIDATE_READ_ONLY'
   where tipo_activo = 'PERFIL' and codigo_activo = v_code and archived_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'TRANSITION_MASS_WRITE_BLOCKED:%', v_n;
  end if;

  select * into a from public.lf_activos
   where tipo_activo = 'PERFIL' and codigo_activo = v_code and archived_at is null;
  if a.estado_original is distinct from 'CANDIDATO_CONTROLADO_READ_ONLY'
     or a.nivel_control is distinct from 'CONTROLADO'
     or a.runtime_estado is distinct from 'CANDIDATE_READ_ONLY'
     or a.estado_documental is distinct from r.estado_documental
     or a.estado_operativo is distinct from r.estado_operativo
     or a.impacto_automatico is distinct from 'BLOQUEADO' then
    raise exception 'TRANSITION_READBACK_MISMATCH';
  end if;

  return jsonb_build_object('status', 'PASS_TRANSITION', 'profile_code', v_code,
    'from_state', v_from, 'to_state', v_to, 'from_state_sha256', v_hash,
    'automatic_impact_still_blocked', true, 'production_enabled', false, 'github_write', false);
end;
$fn$;

revoke all on function public.lf_profile_runtime_transition_v1(jsonb) from public, anon, authenticated;
grant execute on function public.lf_profile_runtime_transition_v1(jsonb) to service_role;

-- Contract v1.2: supersede v0.1.1 and authorise the governed persistent executor (owner chat conformity, 2026-11-05).
do $contract$
declare v_n integer;
begin
  select count(*) into v_n from public.lf_operation_contracts
   where operation_code = 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
     and contract_code = 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1.1-candidate'
     and status = 'CANDIDATO_READ_ONLY';
  if v_n <> 1 then
    raise exception 'TRANSITION_CONTRACT_BASE_NOT_FOUND:%', v_n;
  end if;
  insert into public.lf_operation_contracts
    (operation_code, contract_code, contract_path, contract_sha, required_before_write, allowed, blocked,
     required_after_write, status, created_by_execution_id, updated_by_execution_id)
  select operation_code, 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v1.2',
         'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1_2.json',
         null, required_before_write,
         jsonb_set(jsonb_set(allowed, '{persistent_write_executor}', 'true'::jsonb),
                   '{executor}', '"public.lf_profile_runtime_transition_v1"'::jsonb),
         blocked || '["target_other_than_candidate_read_only","receipt_reuse"]'::jsonb,
         required_after_write, 'CANDIDATO_READ_ONLY', created_by_execution_id, created_by_execution_id
    from public.lf_operation_contracts
   where operation_code = 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
     and contract_code = 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1.1-candidate';
  update public.lf_operation_contracts set status = 'SUPERSEDED'
   where operation_code = 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
     and contract_code = 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1.1-candidate';
end;
$contract$;
