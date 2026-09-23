begin;

alter table private.lf_profile_runtime_queue_v1
  add column if not exists router_execution_envelope jsonb;

alter table private.lf_profile_runtime_queue_v1
  add column if not exists router_execution_envelope_sha256 text;

create or replace function private.fn_lf_profile_runtime_freeze_router_envelope_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_route jsonb;
  v_runtime_adapters jsonb := '[]'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_envelope jsonb;
  v_digest text;
begin
  if new.runtime_target <> 'HETZNER' then
    return new;
  end if;

  if new.operation_code <> 'EJECUCION_PERFIL_LF'
     or nullif(btrim(coalesce(new.profile_code,'')),'') is null
     or nullif(btrim(coalesce(new.profile_slug,'')),'') is null
     or jsonb_typeof(new.profile_source_paths) <> 'array'
     or jsonb_array_length(new.profile_source_paths) = 0
     or nullif(btrim(coalesce(new.input_literal,'')),'') is null then
    raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_QUEUE_IDENTITY_INVALID';
  end if;

  v_route := public.lf_router_resolve_v1(
    new.input_literal,
    new.profile_code,
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  if coalesce(v_route->>'status','') <> 'READY_TO_EXECUTE'
     or coalesce((v_route->>'downstream_execution_allowed')::boolean,false) is not true
     or coalesce(v_route->>'router','') <> 'ACT-0001'
     or coalesce(v_route->>'operation_code','') <> 'EJECUCION_PERFIL_LF'
     or coalesce(v_route#>>'{asset,codigo_activo}','') <> new.profile_code then
    raise exception using
      errcode='23514',
      message='HETZNER_ROUTER_ENVELOPE_NOT_READY',
      detail=left(coalesce(v_route::text,'{}'),1200);
  end if;

  if jsonb_typeof(coalesce(v_route->'adapters','[]'::jsonb)) <> 'array' then
    raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_ADAPTERS_INVALID';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'adapter_code', e.value#>>'{adapter_metadata,canonical_adapter_id}',
        'adapter_version', e.value->>'adapter_version',
        'assurance_revision', coalesce(e.value#>>'{adapter_metadata,assurance_revision}',e.value->>'adapter_version'),
        'activation_source','ROUTER',
        'binding_ref','public.v_lf_router_adapter_bindings:'||(e.value->>'adapter_code')||':'||new.profile_code,
        'target_ref',new.profile_code,
        'ref',e.value#>>'{adapter_metadata,runtime_capsule_path}'
      ) order by e.value#>>'{adapter_metadata,canonical_adapter_id}'
    ),
    '[]'::jsonb
  )
    into v_runtime_adapters
  from jsonb_array_elements(coalesce(v_route->'adapters','[]'::jsonb)) e(value)
  where lower(coalesce(e.value#>>'{adapter_metadata,router_discoverable}','false'))='true'
    and lower(coalesce(e.value#>>'{adapter_metadata,runtime_enabled}','false'))='true';

  if exists (
    select 1
    from jsonb_array_elements(v_runtime_adapters) a(value)
    where nullif(a.value->>'adapter_code','') is null
       or nullif(a.value->>'adapter_version','') is null
       or nullif(a.value->>'assurance_revision','') is null
       or nullif(a.value->>'binding_ref','') is null
       or nullif(a.value->>'ref','') is null
  ) then
    raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_ADAPTER_BINDING_INCOMPLETE';
  end if;

  if jsonb_typeof(v_route->'input_governance')='object' then
    v_required := coalesce(v_route#>'{input_governance,required_by_adapters}','[]'::jsonb);
    if jsonb_typeof(v_required) <> 'array' then
      raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_REQUIRED_ADAPTERS_INVALID';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(v_required) req(code)
      where not exists (
        select 1
        from jsonb_array_elements(v_runtime_adapters) a(value)
        where a.value->>'adapter_code'=req.code
      )
    ) then
      raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_REQUIRED_ADAPTER_NOT_RESOLVED';
    end if;
  end if;

  v_envelope := jsonb_build_object(
    'schema','LF_ROUTER_EXECUTION_ENVELOPE_V1',
    'activation_source','ROUTER',
    'router','ACT-0001',
    'operation_code','EJECUCION_PERFIL_LF',
    'target',jsonb_build_object(
      'profile_code',new.profile_code,
      'profile_slug',new.profile_slug,
      'profile_source_paths',new.profile_source_paths
    ),
    'route',v_route,
    'resolved_runtime_adapters',v_runtime_adapters
  );
  v_digest := 'sha256:' || encode(
    extensions.digest(convert_to(v_envelope::text,'UTF8'),'sha256'),
    'hex'
  );

  if new.router_execution_envelope is not null
     and new.router_execution_envelope is distinct from v_envelope then
    raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_SUPPLIED_VALUE_MISMATCH';
  end if;
  if new.router_execution_envelope_sha256 is not null
     and new.router_execution_envelope_sha256 is distinct from v_digest then
    raise exception using errcode='23514', message='HETZNER_ROUTER_ENVELOPE_SUPPLIED_DIGEST_MISMATCH';
  end if;

  new.router_execution_envelope := v_envelope;
  new.router_execution_envelope_sha256 := v_digest;
  return new;
end;
$function$;

revoke all on function private.fn_lf_profile_runtime_freeze_router_envelope_v1() from public, anon, authenticated;

drop trigger if exists trg_lf_profile_runtime_freeze_router_envelope_v1
  on private.lf_profile_runtime_queue_v1;
create trigger trg_lf_profile_runtime_freeze_router_envelope_v1
before insert on private.lf_profile_runtime_queue_v1
for each row execute function private.fn_lf_profile_runtime_freeze_router_envelope_v1();

create or replace function private.fn_lf_profile_runtime_router_envelope_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.router_execution_envelope is distinct from new.router_execution_envelope
     or old.router_execution_envelope_sha256 is distinct from new.router_execution_envelope_sha256
     or old.operation_code is distinct from new.operation_code
     or old.profile_code is distinct from new.profile_code
     or old.profile_slug is distinct from new.profile_slug
     or old.profile_source_paths is distinct from new.profile_source_paths
     or old.input_literal is distinct from new.input_literal then
    raise exception using errcode='23514', message='PROFILE_RUNTIME_ROUTER_ENVELOPE_IMMUTABLE';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_lf_profile_runtime_router_envelope_immutable_v1() from public, anon, authenticated;

drop trigger if exists trg_lf_profile_runtime_router_envelope_immutable_v1
  on private.lf_profile_runtime_queue_v1;
create trigger trg_lf_profile_runtime_router_envelope_immutable_v1
before update of router_execution_envelope, router_execution_envelope_sha256,
                 operation_code, profile_code, profile_slug, profile_source_paths, input_literal
on private.lf_profile_runtime_queue_v1
for each row execute function private.fn_lf_profile_runtime_router_envelope_immutable_v1();

alter table private.lf_profile_runtime_queue_v1
  drop constraint if exists lf_profile_runtime_router_execution_envelope_ck;
alter table private.lf_profile_runtime_queue_v1
  add constraint lf_profile_runtime_router_execution_envelope_ck
  check (
    runtime_target <> 'HETZNER'
    or (
      jsonb_typeof(router_execution_envelope)='object'
      and router_execution_envelope->>'schema'='LF_ROUTER_EXECUTION_ENVELOPE_V1'
      and router_execution_envelope->>'activation_source'='ROUTER'
      and router_execution_envelope->>'router'='ACT-0001'
      and router_execution_envelope->>'operation_code'='EJECUCION_PERFIL_LF'
      and router_execution_envelope#>>'{target,profile_code}'=profile_code
      and router_execution_envelope#>>'{target,profile_slug}'=profile_slug
      and router_execution_envelope#>'{target,profile_source_paths}'=profile_source_paths
      and router_execution_envelope_sha256 ~ '^sha256:[0-9a-f]{64}$'
    )
  ) not valid;

comment on column private.lf_profile_runtime_queue_v1.router_execution_envelope is
  'Immutable ACT-0001 resolution frozen at queue ingress. Runtime may verify/read it but must never discover or choose routing, adapters, policies, or profile bindings.';
comment on column private.lf_profile_runtime_queue_v1.router_execution_envelope_sha256 is
  'Server-computed SHA-256 of router_execution_envelope canonical jsonb::text bytes at queue ingress.';

commit;